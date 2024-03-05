import Automerge
import Foundation
import OSLog

// replicating main structure from automerge-repo
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageSubsystem.ts
public actor StorageSubsystem<S: StorageProvider> {
    let chunkNamespace = "incChanges"
    var compacting: Bool
    let _storage: StorageProvider
    var latestHeads: [DocumentId: Set<ChangeHash>]
    var chunks: [DocumentId: [Data]]

    public init(_ storage: some StorageProvider) {
        compacting = false
        _storage = storage
        latestHeads = [:]
        chunks = [:]
    }

    public func loadDoc(id: DocumentId) async throws -> Document {
        var combined: Data
        let storageChunks = await _storage.loadRange(key: id, prefix: chunkNamespace)
        let inMemChunks: [Data] = chunks[id] ?? []

        if let baseData = await _storage.load(key: id) {
            // loading all the changes from the base document and any incremental saves available
            combined = baseData
        } else {
            // loading only incremental saves available, the base document doesn't exist in storage
            combined = Data()
        }
        for chunk in inMemChunks {
            combined.append(chunk)
        }
        for chunk in storageChunks {
            combined.append(chunk)
        }
        return try Document(combined)
    }

    private func shouldCompact(for key: DocumentId) async -> Bool {
        if compacting {
            return false
        }
        let baseSize = await _storage.load(key: key)?.count ?? 0
        let chunkSize = await _storage.loadRange(key: key, prefix: chunkNamespace).reduce(0) { incrSize, data in
            incrSize + data.count
        }
        return chunkSize > baseSize
    }

    private func shouldSave(for key: DocumentId, doc: Document) -> Bool {
        guard let storedHeads = self.latestHeads[key] else {
            return true
        }
        let newHeads = doc.heads()
        if newHeads == storedHeads {
            return false
        }
        return true
    }

    public func saveDoc(id: DocumentId, doc: Document) async throws {
        if shouldSave(for: id, doc: doc) {
            if await shouldCompact(for: id) {
                try await compact(id: id, doc: doc, chunks: chunks[id] ?? [])
                self.chunks[id] = []
            } else {
                try await self.saveIncremental(id: id, doc: doc)
            }
        }
    }

    // TODO: update data type from Data to Chunk when validating a byte array as a partial set of changes is available from Automerge core
    public func compact(id: DocumentId, doc _: Document, chunks _: [Data]) async throws {
        compacting = true
        let compacted = try await self.loadDoc(id: id)
        // only remove the chunks AFTER the save is complete
        await _storage.save(key: id, data: compacted.save())
        await _storage.removeRange(key: id, prefix: chunkNamespace)
        latestHeads[id] = compacted.heads()
        compacting = false
    }

    public func saveIncremental(id: DocumentId, doc: Document) async throws {
        var chunkCollection = chunks[id] ?? []
        let oldHeads = latestHeads[id] ?? Set<ChangeHash>()
        let incrementals = try doc.encodeChangesSince(heads: oldHeads)
        chunkCollection.append(incrementals)
        chunks[id] = chunkCollection
        await _storage.addToRange(key: id, prefix: chunkNamespace, data: incrementals)
        latestHeads[id] = doc.heads()
    }

    public func loadSyncState(id _: DocumentId, storageId _: SyncV1.STORAGE_ID) async -> SyncState {
        SyncState()
    }

    public func saveSyncState(id _: DocumentId, storageId _: SyncV1.STORAGE_ID, state _: SyncState) async {}
}
