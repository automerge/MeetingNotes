import Automerge
import OSLog
import PotentCBOR
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// An Automerge document that is CBOR encoded with a document identifier.
    static var automerge: UTType {
        UTType(exportedAs: "com.github.automerge.meetingnotes")
    }
}

/// A CBOR encoded wrapper around a serialized Automerge document.
///
/// The `id` is a unique identifier that provides a "new document" identifier for the purpose of comparing two documents
/// to determine if they were branched from the same root document.
struct WrappedAutomergeFile: Codable {
    let id: UUID
    let data: Data
}

/// The concrete subclass of a reference-based file document.
///
/// The Document subclass includes saving the application model ``MeetingNotesModel`` into a managed Automerge document,
/// and serializing that document out to the filesystem as a ``WrappedAutomergeFile``.
/// The `WrappedAutomergeFile` uses `CBOR` encoding to add a document identifier to the file format.
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
    let logger = Logger(subsystem: "Document", category: "Serialization")
    let fileEncoder = CBOREncoder()
    let fileDecoder = CBORDecoder()
    let modelEncoder: AutomergeEncoder
    let modelDecoder: AutomergeDecoder
    var doc: Document
    var model: MeetingNotesModel

    static var readableContentTypes: [UTType] { [.automerge] }

    init() {
        doc = Document()
        modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        modelDecoder = AutomergeDecoder(doc: doc)
        model = MeetingNotesModel(title: "Untitled")
        do {
            // Establish the schema in the new Automerge document by encoding the model.
            try modelEncoder.encode(model)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    /// Updates the Automerge document with the current value from the model.
    func storeModelUpdates() throws {
        try modelEncoder.encode(model)
    }

    /// Updates the model document with any changed values in the Automerge document.
    func getModelUpdates() throws {
        model = try modelDecoder.decode(MeetingNotesModel.self)
    }

    required init(configuration: ReadConfiguration) throws {
        guard let filedata = configuration.file.regularFileContents
        else {
            logger
                .error(
                    "Opened file \(String(describing: configuration.file.filename), privacy: .public) has no associated data."
                )
            throw CocoaError(.fileReadCorruptFile)
        }

        // The binary format of the document is a CBOR encoded file. The goal being to wrap the
        // raw automerge document serialization with an 'envelope' that includes an origin ID,
        // so that an application can know if the document stemmed from the same original source
        // or if they're entirely independent.
        let wrappedDocument = try fileDecoder.decode(WrappedAutomergeFile.self, from: filedata)
        // And then deserialize the Automerge document from the wrappers data
        doc = try Document(wrappedDocument.data)
        modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        modelDecoder = AutomergeDecoder(doc: doc)
        model = try modelDecoder.decode(MeetingNotesModel.self)
        // Verify the ID in the document matches the one in the wrapper
        if model.id != wrappedDocument.id {
            logger
                .error(
                    "Internal document id: \(self.model.id, privacy: .public) doesn't match the origin ID in the file wrapper (\(wrappedDocument.id, privacy: .public)"
                )
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func snapshot(contentType _: UTType) throws -> Document {
        try modelEncoder.encode(model)
        return doc
    }

    func fileWrapper(snapshot: Document, configuration _: WriteConfiguration) throws -> FileWrapper {
        // Using the updated Automerge document returned from snapshot, create a wrapper
        // with the origin ID from the serialized automerge file.
        let wrappedDocument = WrappedAutomergeFile(id: model.id, data: snapshot.save())
        // Encode that wrapper using CBOR encoding
        let filedata = try fileEncoder.encode(wrappedDocument)
        // And hand that file to the FileWrapper for the operating system to save, transfer, etc.
        let fileWrapper = FileWrapper(regularFileWithContents: filedata)
        return fileWrapper
    }

    // MARK: sample document for SwiftUI previews

    static func sample() -> MeetingNotesDocument {
        let newDoc = MeetingNotesDocument()
        newDoc.model.agenda.append(AgendaItem(title: "First topic", discussion: Automerge.Text("")))
        newDoc.model.agenda.append(AgendaItem(title: "Second topic", discussion: Automerge.Text("")))
        try! newDoc.storeModelUpdates()
        return newDoc
    }
}
