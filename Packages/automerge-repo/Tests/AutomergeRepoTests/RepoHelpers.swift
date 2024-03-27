import Automerge
@testable import AutomergeRepo
import AutomergeUtilities
import Foundation

public enum RepoHelpers {
    static func documentWithData() throws -> Document {
        let newDoc = Document()
        let txt = try newDoc.putObject(obj: .ROOT, key: "words", ty: .Text)
        try newDoc.updateText(obj: txt, value: "Hello World!")
        return newDoc
    }

    static func docHandleWithData() throws -> DocHandle {
        let newDoc = Document()
        let txt = try newDoc.putObject(obj: .ROOT, key: "words", ty: .Text)
        try newDoc.updateText(obj: txt, value: "Hello World!")
        return DocHandle(id: DocumentId(), doc: newDoc)
    }

    static func equalContents(doc1: Document, doc2: Document) -> Bool {
        do {
            let doc1Contents = try doc1.parseToSchema(doc1, from: .ROOT)
            let doc2Contents = try doc2.parseToSchema(doc1, from: .ROOT)
            return doc1Contents == doc2Contents
        } catch {
            return false
        }
    }
}
