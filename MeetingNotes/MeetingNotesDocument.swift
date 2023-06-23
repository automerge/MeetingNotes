import SwiftUI
import UniformTypeIdentifiers
import Automerge

extension UTType {
    static var automerge: UTType {
        UTType(exportedAs: "com.github.automerge.localfirst")
    }
}

class MeetingNotesDocument: ReferenceFileDocument {
    // NOTE(heckj): As of Automerge 2.0 - Automerge doesn't have an internal
    // document identifier that's easily available to use for comparison
    // to determine if documents have a "shared origin" or not.

    // Upstream automerge is working around this with wrapping the data
    // stream from "core" Automerge with a simple wrapper (CBOR) and tacking
    // on an automatically generated UUID() as that identifier.

    let enc: AutomergeEncoder
    let dec: AutomergeDecoder
    var doc: Document
    var model: MeetingNotesModel

    static var readableContentTypes: [UTType] { [.automerge] }

    init() {
        doc = Document()
        enc = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        dec = AutomergeDecoder(doc: doc)
        model = MeetingNotesModel(title: "Untitled", summary: Automerge.Text(""))
        do {
            try enc.encode(model)
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        doc = try! Document(data)
        enc = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
        dec = AutomergeDecoder(doc: doc)
        model = try dec.decode(MeetingNotesModel.self)
    }

    func snapshot(contentType _: UTType) throws -> Document {
        try enc.encode(model)
        return doc
    }

    func fileWrapper(snapshot: Document, configuration _: WriteConfiguration) throws -> FileWrapper {
        let data = snapshot.save()
        let fileWrapper = FileWrapper(regularFileWithContents: data)
        return fileWrapper
    }
}
