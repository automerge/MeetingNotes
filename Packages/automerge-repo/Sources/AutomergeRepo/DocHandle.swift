import class Automerge.Document

public struct DocHandle: Sendable {
    let id: DocumentId
    let doc: Document

    init(id: DocumentId, doc: Document) {
        self.id = id
        self.doc = doc
    }
}
