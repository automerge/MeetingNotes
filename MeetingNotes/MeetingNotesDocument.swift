import Automerge
import OSLog
import PotentCBOR
import SwiftUI
import UniformTypeIdentifiers

/// A collection of User Default keys for the app.
enum MeetingNotesDefaultKeys {
    /// The key to the string that the app broadcasts to represent you when sharing and syncing MeetingNotes.
    static let sharingIdentity = "sharingIdentity"
}

extension UTType {
    /// An Automerge document that is CBOR encoded with a document identifier.
    static var meetingnote: UTType {
        UTType(exportedAs: "com.github.automerge.meetingnotes")
    }
}

/// A CBOR encoded wrapper around a serialized Automerge document.
///
/// The `id` is a unique identifier that provides a "new document" identifier for the purpose of comparing two documents
/// to determine if they were branched from the same root document.
struct WrappedAutomergeDocument: Codable {
    let id: UUID
    let data: Data
    static let fileEncoder = CBOREncoder()
    static let fileDecoder = CBORDecoder()
}

extension WrappedAutomergeDocument: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .meetingnote, encoder: fileEncoder, decoder: fileDecoder)
    }
}

enum MergeError: LocalizedError {
    case NoSharedHistory
}

/// The concrete subclass of a reference-based file document.
///
/// The Document subclass includes saving the application model ``MeetingNotesModel`` into a managed Automerge document,
/// and serializing that document out to the filesystem as a ``WrappedAutomergeDocument``.
/// The `WrappedAutomergeDocument` uses `CBOR` encoding to add a document identifier to the file format.
///
/// With [Automerge](https://automerge.org) version 2.0, a document doesn't have an internal  document identifier that's
/// easily available to use for comparison
/// to determine if documents have a "shared origin".
/// With Automerge (and other CRDTs), merging of documents is predicated on having a shared history that the algorithms
/// can use to merge the causal history in an expected format.
/// It is possible to merge without that shared history, but the results of the merging during the sync "appear" to be
/// far more random;
/// one peer consistently "winning" over the other with conflicting causal data points.
///
/// The upstream project is working around this by wrapping the data stream from "core" Automerge with a simple wrapper
/// (using `CBOR` encoding) and tacking on an automatically generated `UUID` as that identifier.
///
/// For more information about `CBOR` encoding, see [CBOR specification overview](https://cbor.io).
final class MeetingNotesDocument: ReferenceFileDocument {
    let fileEncoder = CBOREncoder()
    let fileDecoder = CBORDecoder()
    let modelEncoder: AutomergeEncoder
    let modelDecoder: AutomergeDecoder
    let id: UUID
    var doc: Document
    var sharingIdentity: String

    let syncController: DocumentSyncCoordinator

    @Published
    var model: MeetingNotesModel

    static var readableContentTypes: [UTType] { [.meetingnote] }

    static func defaultSharingIdentity() -> String {
        #if os(iOS)
        UIDevice().name
        #elseif os(macOS)
        Host.current().localizedName ?? "MeetingNotes User"
        #endif
    }

    init() {
        Logger.document.debug("INITIALIZING NEW DOCUMENT")

        id = UUID()
        doc = Document()
        model = MeetingNotesModel(title: "Untitled")
        modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        modelDecoder = AutomergeDecoder(doc: doc)
        sharingIdentity = UserDefaults.standard
            .string(forKey: MeetingNotesDefaultKeys.sharingIdentity) ?? MeetingNotesDocument.defaultSharingIdentity()
        syncController = DocumentSyncCoordinator(name: sharingIdentity)

        do {
            // Establish the schema in the new Automerge document by encoding the model.
            try modelEncoder.encode(model)
        } catch {
            fatalError(error.localizedDescription)
        }
        syncController.document = self
    }

    required init(configuration: ReadConfiguration) throws {
        guard let filedata = configuration.file.regularFileContents
        else {
            Logger.document.error(
                "Opened file \(String(describing: configuration.file.filename), privacy: .public) has no associated data."
            )
            throw CocoaError(.fileReadCorruptFile)
        }

        Logger.document.debug("LOADING DOCUMENT FROM file data")
        // The binary format of the document is a CBOR encoded file. The goal being to wrap the
        // raw automerge document serialization with an 'envelope' that includes an origin ID,
        // so that an application can know if the document stemmed from the same original source
        // or if they're entirely independent.
        let wrappedDocument = try fileDecoder.decode(WrappedAutomergeDocument.self, from: filedata)
        // Set the identifier of this document, external from the Automerge document.
        id = wrappedDocument.id
        // Then deserialize the Automerge document from the wrappers data.
        doc = try Document(wrappedDocument.data)
        modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        modelDecoder = AutomergeDecoder(doc: doc)
        model = try modelDecoder.decode(MeetingNotesModel.self)

        sharingIdentity = UserDefaults.standard
            .string(forKey: MeetingNotesDefaultKeys.sharingIdentity) ?? MeetingNotesDocument.defaultSharingIdentity()
        syncController = DocumentSyncCoordinator(name: sharingIdentity)
        syncController.document = self
    }

    deinit {
        syncController.deactivate()
    }

    func snapshot(contentType _: UTType) throws -> Document {
        try modelEncoder.encode(model)
        // Logger.document.debug("Writing the model back into the Automerge document")
        return doc
    }

    func wrappedDocument() -> WrappedAutomergeDocument {
        do {
            let data = try self.snapshot(contentType: .meetingnote).save()
            return WrappedAutomergeDocument(id: id, data: data)
        } catch {
            abort()
        }
    }

    func fileWrapper(snapshot: Document, configuration _: WriteConfiguration) throws -> FileWrapper {
        // Logger.document.debug("Returning FileWrapper handle with serialized data")
        // Using the updated Automerge document returned from snapshot, create a wrapper
        // with the origin ID from the serialized automerge file.
        let wrappedDocument = WrappedAutomergeDocument(id: id, data: snapshot.save())
        // Encode that wrapper using CBOR encoding
        let filedata = try fileEncoder.encode(wrappedDocument)
        // And hand that file to the FileWrapper for the operating system to save, transfer, etc.
        let fileWrapper = FileWrapper(regularFileWithContents: filedata)
        return fileWrapper
    }

    /// Updates the Automerge document with the current value from the model.
    func storeModelUpdates() throws {
        try modelEncoder.encode(model)
        self.objectWillChange.send()
    }

    /// Updates the model document with any changed values in the Automerge document.
    func getModelUpdates() throws {
        // Logger.document.debug("Updating model from Automerge document.")
        model = try modelDecoder.decode(MeetingNotesModel.self)
    }

    func mergeFile(_ fileURL: URL) -> Result<Bool, Error> {
        precondition(fileURL.isFileURL)
        do {
            let fileData = try Data(contentsOf: fileURL)
            let newWrappedDocument = try fileDecoder.decode(WrappedAutomergeDocument.self, from: fileData)
            if newWrappedDocument.id != self.id {
                throw MergeError.NoSharedHistory
            }
            let newAutomergeDoc = try Document(newWrappedDocument.data)
            try doc.merge(other: newAutomergeDoc)
            model = try modelDecoder.decode(MeetingNotesModel.self)
            return .success(true)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Sample document for SwiftUI previews

    /// Creates a same meeting notes document with two empty agenda items.
    ///
    /// Intended for internal preview usage.
    static func sample() -> MeetingNotesDocument {
        let newDoc = MeetingNotesDocument()
        newDoc.model.agendas.append(AgendaItem(title: "First topic", discussion: AutomergeText("")))
        newDoc.model.agendas.append(AgendaItem(title: "Second topic", discussion: AutomergeText("")))
        try! newDoc.storeModelUpdates()
        return newDoc
    }
}
