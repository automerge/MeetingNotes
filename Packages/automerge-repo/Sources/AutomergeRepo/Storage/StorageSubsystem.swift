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
    
    var storedChunkSize: [DocumentId:Int]
    var memoryChunkSize: [DocumentId:Int]
    var storedDocSize: [DocumentId:Int]
    
    var chunks: [DocumentId: [Data]]

    public init(_ storage: some StorageProvider) {
        compacting = false
        _storage = storage
        latestHeads = [:]
        chunks = [:]
        
        // memo-ized sizes so that we don't have to potentially re-iterate through
        // the storage provider (disk accesses, or even network accesses) to get a
        // size determination to know if we should compact or not. (used in
        // `shouldCompact(:DocumentId)`
        storedChunkSize = [:]
        memoryChunkSize = [:]
        storedDocSize = [:]
    }

    public func loadDoc(id: DocumentId) async throws -> Document {
        var combined: Data
        let storageChunks = await _storage.loadRange(key: id, prefix: chunkNamespace)
        let inMemChunks: [Data] = chunks[id] ?? []

        if let baseData = await _storage.load(key: id) {
            // loading all the changes from the base document and any incremental saves available
            combined = baseData
            storedDocSize[id] = baseData.count
        } else {
            // loading only incremental saves available, the base document doesn't exist in storage
            combined = Data()
            storedDocSize[id] = 0
        }
        
        var inMemSize = memoryChunkSize[id] ?? 0
        for chunk in inMemChunks {
            inMemSize += chunk.count
            combined.append(chunk)
        }
        memoryChunkSize[id] = inMemSize
        
        var storedChunks = storedChunkSize[id] ?? 0
        for chunk in storageChunks {
            storedChunks += chunk.count
            combined.append(chunk)
        }
        storedChunkSize[id] = storedChunks

        return try Document(combined)
    }

    private func shouldCompact(_ key: DocumentId) async -> Bool {
        if compacting {
            return false
        }
        let inMemSize = memoryChunkSize[key] ?? (chunks[key] ?? []).reduce(0) { incrSize, data in
            incrSize + data.count
        }
        
        let baseSize: Int
        if let i = storedDocSize[key] {
            baseSize = i
        } else {
            baseSize =  await _storage.load(key: key)?.count ?? 0
        }
        
        let chunkSize: Int
        if let j = storedChunkSize[key] {
            chunkSize = j
        } else {
            chunkSize = await _storage.loadRange(key: key, prefix: chunkNamespace).reduce(0) { incrSize, data in
                incrSize + data.count
            }
        }
        return chunkSize > baseSize || inMemSize > baseSize
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
            if await shouldCompact(id) {
                try await compact(id: id, doc: doc, chunks: chunks[id] ?? [])
                self.chunks[id] = []
            } else {
                try await self.saveIncremental(id: id, doc: doc)
            }
        }
    }

    // TODO: update data type from Data to Chunk when validating a byte array as a partial set of changes is available from Automerge cores
    public func compact(id: DocumentId, doc _: Document, chunks _: [Data]) async throws {
        compacting = true
        var combined: Data
        if let baseData = await _storage.load(key: id) {
            // loading all the changes from the base document and any incremental saves available
            combined = baseData
        } else {
            // loading only incremental saves available, the base document doesn't exist in storage
            combined = Data()
        }
        
        let inMemChunks: [Data] = chunks[id] ?? []
        var foundChunkHashValues: [Int] = []
        for chunk in inMemChunks {
            foundChunkHashValues.append(chunk.hashValue)
            combined.append(chunk)
        }
        
        let storageChunks = await _storage.loadRange(key: id, prefix: chunkNamespace)
        for chunk in storageChunks {
            combined.append(chunk)
        }

        let compactedDoc = try Document(combined)
        
        let compactedData = compactedDoc.save()
        // only remove the chunks AFTER the save is complete
        await _storage.save(key: id, data: compactedData)
        storedDocSize[id] = compactedData.count
        latestHeads[id] = compactedDoc.heads()
        
        // refresh the inMemChunks in case its changed (possible with re-entrancy, due to
        // the possible suspension points at each of the above `await` statements since we
        // grabbed the in memeory reference and made a copy)
        var updatedMemChunks = chunks[id] ?? []
        for d in inMemChunks {
            if let indexToRemove = updatedMemChunks.firstIndex(of: d) {
                updatedMemChunks.remove(at: indexToRemove)
            }
        }
        chunks[id] = updatedMemChunks
        memoryChunkSize[id] = updatedMemChunks.reduce(0) { incrSize, data in
            incrSize + data.count
        }
        
        // now iterate through and remove the stored chunks we loaded earlier
        // Doing this last, intentionally - it's another suspension point, and IF someone
        // reads the base document and appends the found changes in a load, they'll still
        // end up with the same document, so these can safely be removed _after_ the new
        // compacted document has been stored away by the underlying storage provider.
        await _storage.removeRange(key: id, prefix: chunkNamespace, data: storageChunks)
        storedChunkSize[id] = await _storage.loadRange(key: id, prefix: chunkNamespace).reduce(0) { incrSize, data in
            incrSize + data.count
        }

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
