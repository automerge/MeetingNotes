import struct Foundation.Data

// loose adaptation from automerge-repo storage interface
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageAdapter.ts
public protocol StorageProvider {
    // TODO: update type from Data to 'Chunk'
    // to represent the encoded changes of an Automerge document
    func load(key: DocumentId) async -> Data?

    // TODO: update type from Data to 'Chunk'
    // to represent the encoded changes of an Automerge document
    func save(key: DocumentId, data: Data) async

    func remove(key: DocumentId) async

    // MARK: Incremental Load Support

    // TODO: update type from Data to 'Chunk'
    // to represent an encoded partial set of changes to an Automerge document
    func addToRange(key: DocumentId, prefix: String, data: Data) async

    // TODO: update type from Data to 'Chunk'
    // to represent an encoded partial set of changes to an Automerge document
    func loadRange(key: DocumentId, prefix: String) async -> [Data]

    func removeRange(key: DocumentId, prefix: String) async
}
