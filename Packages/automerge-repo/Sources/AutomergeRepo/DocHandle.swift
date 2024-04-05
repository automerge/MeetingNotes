import class Automerge.Document

public struct DocHandle: Sendable {
    public let id: DocumentId
    public let doc: Document

    init(id: DocumentId, doc: Document) {
        self.id = id
        self.doc = doc
    }
}
