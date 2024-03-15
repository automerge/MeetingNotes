import struct Foundation.Data

// loose adaptation from automerge-repo storage interface
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageAdapter.ts
/// A type that provides a an interface for persisting the changes of Automerge documents by Id
public protocol StorageProvider: Sendable {
    var id: STORAGE_ID { get }

    func load(id: DocumentId) async throws -> Data?
    func save(id: DocumentId, data: Data) async throws
    func remove(id: DocumentId) async throws

    // MARK: Incremental Load Support

    func addToRange(id: DocumentId, prefix: String, data: Data) async throws
    func loadRange(id: DocumentId, prefix: String) async throws -> [Data]
    func removeRange(id: DocumentId, prefix: String, data: [Data]) async throws
}
