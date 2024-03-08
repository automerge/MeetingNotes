import struct Foundation.Data

// loose adaptation from automerge-repo storage interface
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageAdapter.ts
/// A type that provides a an interface for persisting the changes of Automerge documents by Id
public protocol StorageProvider {
    var id: STORAGE_ID { get }

    func load(key: DocumentId) async throws -> Data?
    func save(key: DocumentId, data: Data) async throws
    func remove(key: DocumentId) async throws

    // MARK: Incremental Load Support

    func addToRange(key: DocumentId, prefix: String, data: Data) async throws
    func loadRange(key: DocumentId, prefix: String) async throws -> [Data]
    func removeRange(key: DocumentId, prefix: String, data: [Data]) async throws
}
