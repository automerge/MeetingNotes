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

struct WrappedAutomergeFile: Codable {
    let id: UUID
    let data: Data
}

class MeetingNotesDocument: ReferenceFileDocument {
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
    let enc: AutomergeEncoder
    let dec: AutomergeDecoder
    var doc: Document
    var model: MeetingNotesModel

    static var readableContentTypes: [UTType] { [.automerge] }

    init() {
        doc = Document()
        enc = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        dec = AutomergeDecoder(doc: doc)
        model = MeetingNotesModel(title: "Untitled")
        do {
            try enc.encode(model)
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
        // Binary is a CBOR encoded file that includes an origin ID, so decode that into
        // a wrapper struct
        let wrappedDocument = try fileDecoder.decode(WrappedAutomergeFile.self, from: filedata)
        // And then deserialize the Automerge document from the wrappers data
        doc = try Document(wrappedDocument.data)
        enc = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        dec = AutomergeDecoder(doc: doc)
        model = try dec.decode(MeetingNotesModel.self)
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
        try enc.encode(model)
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
