import Automerge
import AutomergeRepo
import Combine
import OSLog
import PotentCBOR
import SwiftUI
import UniformTypeIdentifiers

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
    let id: DocumentId
    let data: Data
    static let fileEncoder = CBOREncoder()
    static let fileDecoder = CBORDecoder()
}

extension WrappedAutomergeDocument: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .meetingnote, encoder: fileEncoder, decoder: fileDecoder)
    }
}

/// Document merging errors
enum MergeError: LocalizedError {
    /// The documents don't have a shared history.
    case NoSharedHistory
}

/// The concrete subclass of a reference-based file document.
///
/// The Document subclass includes saving the application model ``MeetingNotesModel`` into a managed Automerge document,
/// and serializing that document out to the filesystem as a ``WrappedAutomergeDocument``.
/// The `WrappedAutomergeDocument` uses `CBOR` encoding to add a document identifier to the file format.
///
/// With [Automerge](https://automerge.org) version 2.0, a document doesn't have an internal  document identifier that's
/// easily available to use for comparison to determine if documents have a "shared origin".
/// With Automerge (and other CRDTs), merging of documents is predicated on having a shared history that the algorithms
/// can use to merge the causal history in an expected format.
/// It is possible to merge without that shared history, but the results of the merging during the sync "appear" to be
/// far more random; one peer consistently "winning" over the other with conflicting causal data points.
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
    let id: DocumentId
    var doc: Document

    @Published
    var model: MeetingNotesModel

    var syncedDocumentTrigger: Cancellable?

    static var readableContentTypes: [UTType] { [.meetingnote] }

    init() {
        Logger.document.debug("INITIALIZING NEW DOCUMENT")
        id = DocumentId()
        doc = Document()
        let newModel = MeetingNotesModel(title: "Untitled")
        model = newModel
        modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        modelDecoder = AutomergeDecoder(doc: doc)

        do {
            // Establish the schema in the new Automerge document by encoding the model.
            try modelEncoder.encode(newModel)
        } catch {
            fatalError(error.localizedDescription)
        }

        syncedDocumentTrigger = doc.objectWillChange.sink {
            self.objectWillChange.send()
        }
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
        Logger.document.debug("Starting to CBOR decode from \(filedata.count, privacy: .public) bytes")
        let wrappedDocument = try fileDecoder.decode(WrappedAutomergeDocument.self, from: filedata)
        // Set the identifier of this document, external from the Automerge document.
        id = wrappedDocument.id
        // Then deserialize the Automerge document from the wrappers data.
        doc = try Document(wrappedDocument.data)
        Logger.document
            .debug(
                "Created Automerge doc of ID \(self.id, privacy: .public) from CBOR encoded data of \(wrappedDocument.data.count, privacy: .public) bytes"
            )
        modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        modelDecoder = AutomergeDecoder(doc: doc)
        do {
            model = try modelDecoder.decode(MeetingNotesModel.self)
        } catch let DecodingError.dataCorrupted(context) {
            Logger.document.error("\(context.debugDescription, privacy: .public)")
            fatalError()
        } catch let DecodingError.keyNotFound(key, context) {
            Logger.document
                .error(
                    "Key '\(key.debugDescription, privacy: .public)' not found: \(context.debugDescription, privacy: .public)"
                )
            Logger.document.error("codingPath: \(context.codingPath.debugDescription, privacy: .public)")
            fatalError()
        } catch let DecodingError.valueNotFound(value, context) {
            Logger.document
                .error("Value '\(value, privacy: .public)' not found: \(context.debugDescription, privacy: .public)")
            Logger.document.error("codingPath: \(context.codingPath.debugDescription, privacy: .public)")
            fatalError()
        } catch let DecodingError.typeMismatch(type, context) {
            Logger.document.error("Type '\(type)' mismatch: \(context.debugDescription, privacy: .public)")
            Logger.document.error("codingPath: \(context.codingPath, privacy: .public)")
            fatalError()
        } catch {
            Logger.document.error("error: \(error, privacy: .public)")
            fatalError()
        }
        Logger.document
            .debug("finished loading from \(String(describing: configuration.file.filename), privacy: .public)")
        syncedDocumentTrigger = doc.objectWillChange
            // slow down the rate at which updates can appear so that the whole SwiftUI view
            // structure won't be reset too frequently, but IS updated when changes come in from
            // a syncing mechanism.
            .throttle(for: 1.0, scheduler: DispatchQueue.main, latest: true)
            .receive(on: RunLoop.main)
            .sink {
                do {
                    try self.getModelUpdates()
                } catch {
                    fatalError("Error occurred while updating the model from the Automerge document: \(error)")
                }
                self.objectWillChange.send()
            }
    }

    deinit {
        Logger.document.debug("DEINIT of MeetingNotesDocument, documentId: \(self.id, privacy: .public)")
        syncedDocumentTrigger?.cancel()
        syncedDocumentTrigger = nil
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
