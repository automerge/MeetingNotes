import Automerge
import OSLog
import PotentCBOR
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var automerge: UTType {
        UTType(exportedAs: "com.github.automerge.localfirst")
    }
}

/// A CBOR encoded wrapper around a serialized Automerge document.
///
/// The `id` is a unique identifier that provides a "new document" identifier for the purpose of comparing two documents to determine if they were branched from the same root document.
struct WrappedAutomergeFile: Codable {
    let id: UUID
    let data: Data
}

final class MeetingNotesDocument: ReferenceFileDocument {
    // NOTE(heckj): With Automerge 2.0, a document doesn't have an internal
    // document identifier that's easily available to use for comparison
    // to determine if documents have a "shared origin". (You really only
    // want to merge documents if they have a shared history - you can still
    // merge without that shared history, but the results of the merging
    // during the sync "appear" to be far more random, with one peer consistently
    // "winning" over the other with conflicting causal data points.

    // The upstream project is working around this by wrapping the data
    // stream from "core" Automerge with a simple wrapper (using CBOR encoding)
    // and tacking on an automatically generated UUID() as that identifier.

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
}
