import struct Foundation.Data

// loose adaptation from automerge-repo storage interface
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageAdapter.ts
public protocol StorageProvider {
    func load(key: DocumentId) async -> Data?
    func save(key: DocumentId, data: Data) async
    func remove(key: DocumentId) async

    // MARK: Incremental Load Support

    func addToRange(key: DocumentId, prefix: String, data: Data) async
    func loadRange(key: DocumentId, prefix: String) async -> [Data]
    func removeRange(key: DocumentId, prefix: String) async
}
