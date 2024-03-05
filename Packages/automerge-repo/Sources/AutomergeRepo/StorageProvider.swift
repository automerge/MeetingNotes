import class Automerge.Document
import struct Automerge.SyncState
import struct Foundation.Data
import struct Foundation.UUID

// loose adaptation from automerge-repo storage interface
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageAdapter.ts
public protocol StorageProvider {
    func load(key: String) async -> Data
    func save(key: String, data: Data) async
    func remove(key: String) async

    func loadRange(key: String, prefix: String) async -> [Data]
    func removeRange(prefix: String) async

    // higher level functions that use above:
}

// replicating main structure from automerge-repo
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageSubsystem.ts
public struct StorageSubsystem {
    public func loadDoc(id _: DocumentId) async -> Document {
        Document()
    }

    public func saveDoc(id _: DocumentId, doc _: Document) async {}

    public func compact(id _: DocumentId, doc _: Document, chunks _: [Data]) async {}
    public func saveIncremental(id _: DocumentId, doc _: Document) async {}

    public func loadSyncState(id _: DocumentId, storageId _: UUID) async -> SyncState {
        SyncState()
    }

    public func saveSyncState(id _: DocumentId, storageId _: UUID, state _: SyncState) async {}
}
