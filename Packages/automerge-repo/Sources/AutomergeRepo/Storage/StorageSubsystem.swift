import class Automerge.Document
import struct Automerge.SyncState
import struct Foundation.Data
import struct Foundation.UUID

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
