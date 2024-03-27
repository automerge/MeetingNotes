import Automerge
import Foundation
import OSLog

// inspired from automerge-repo:
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/storage/StorageSubsystem.ts

/// A type that provides coordinated, concurrency safe access to persist Automerge documents.
public actor DocumentStorage {
    let chunkNamespace = "incrChanges"
    var compacting: Bool
    let _storage: any StorageProvider
    var latestHeads: [DocumentId: Set<ChangeHash>]

    var storedChunkSize: [DocumentId: Int]
    var memoryChunkSize: [DocumentId: Int]
    var storedDocSize: [DocumentId: Int]

    var chunks: [DocumentId: [Data]]

    /// Creates a new concurrency safe document storage instance to manage changes to Automerge documents.
    /// - Parameter storage: The storage provider
    public init(_ storage: some StorageProvider) {
        compacting = false
        _storage = storage
        latestHeads = [:]
        chunks = [:]

        // memo-ized sizes of documents and chunks so that we don't always have to
        // iterate through the storage provider (disk accesses, or even network accesses)
        // to get a size determination to know if we should compact or not.
        // (used in function`shouldCompact(:DocumentId)`)
        storedChunkSize = [:]
        memoryChunkSize = [:]
        storedDocSize = [:]
    }

    public var id: STORAGE_ID {
        _storage.id
    }

    /// Removes a document from persistent storage.
    /// - Parameter id: The id of the document to remove.
    public func purgeDoc(id: DocumentId) async throws {
        try await _storage.remove(id: id)
    }

    /// Returns an existing, or creates a new, document for the document Id you provide.
    ///
    /// The method throws errors from the underlying storage system or Document errors if the
    /// loaded data was corrupt or incorrect.
    ///
    /// - Parameter id: The document Id
    /// - Returns: An automerge document.
    public func loadDoc(id: DocumentId) async throws -> Document {
        var combined: Data
        let storageChunks = try await _storage.loadRange(id: id, prefix: chunkNamespace)
        if chunks[id] == nil {
            chunks[id] = []
        }
        let inMemChunks: [Data] = chunks[id] ?? []

        if let baseData = try await _storage.load(id: id) {
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
        let combinedDoc = try Document(combined)
        latestHeads[id] = combinedDoc.heads()

        return combinedDoc
    }

    /// Determine if a documentId should be compacted.
    /// - Parameter key: the document Id to analyze
    /// - Returns: a Boolean value that indicates whether the document should be compacted.
    func shouldCompact(_ key: DocumentId) async throws -> Bool {
        if compacting {
            return false
        }
        let inMemSize = memoryChunkSize[key] ?? (chunks[key] ?? []).reduce(0) { incrSize, data in
            incrSize + data.count
        }

        let baseSize = if let i = storedDocSize[key] {
            i
        } else {
            try await _storage.load(id: key)?.count ?? 0
        }

        let chunkSize = if let j = storedChunkSize[key] {
            j
        } else {
            try await _storage.loadRange(id: key, prefix: chunkNamespace).reduce(0) { incrSize, data in
                incrSize + data.count
            }
        }
        return chunkSize > baseSize || inMemSize > baseSize
    }

    /// Determine if the document provided has changes not represented by the underlying storage system
    /// - Parameters:
    ///   - key: The Id of the document
    ///   - doc: The Automerge document
    /// - Returns: A Boolean value that indicates the document has changes.
    func shouldSave(for key: DocumentId, doc: Document) -> Bool {
        guard let storedHeads = self.latestHeads[key] else {
            return true
        }
        let newHeads = doc.heads()
        if newHeads == storedHeads {
            return false
        }
        return true
    }

    /// Saves a document to the storage backend, compacting it if needed.
    /// - Parameters:
    ///   - id: The Id of the document
    ///   - doc: The automerge document
    public func saveDoc(id: DocumentId, doc: Document) async throws {
        if shouldSave(for: id, doc: doc) {
            if try await shouldCompact(id) {
                try await compact(id: id, doc: doc)
                self.chunks[id] = []
            } else {
                try await self.saveIncremental(id: id, doc: doc)
            }
        }
    }

    /// A concurrency safe compaction routine to consolidate in-memory and stored incremental changes into a compacted
    /// Automerge document.
    /// - Parameters:
    ///   - id: The document Id to compact
    ///   - doc: The document to compact.
    public func compact(id: DocumentId, doc: Document) async throws {
        compacting = true
        let providedData = doc.save()
        var combined: Data = if let baseData = try await _storage.load(id: id) {
            // loading all the changes from the base document and any incremental saves available
            baseData
        } else {
            // loading only incremental saves available, the base document doesn't exist in storage
            Data()
        }

        combined.append(providedData)

        let inMemChunks: [Data] = chunks[id] ?? []
        var foundChunkHashValues: [Int] = []
        for chunk in inMemChunks {
            foundChunkHashValues.append(chunk.hashValue)
            combined.append(chunk)
        }

        let storageChunks = try await _storage.loadRange(id: id, prefix: chunkNamespace)
        for chunk in storageChunks {
            combined.append(chunk)
        }

        let compactedDoc = try Document(combined)

        let compactedData = compactedDoc.save()
        // only remove the chunks AFTER the save is complete
        try await _storage.save(id: id, data: compactedData)
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
        try await _storage.removeRange(id: id, prefix: chunkNamespace, data: storageChunks)
        storedChunkSize[id] = try await _storage.loadRange(id: id, prefix: chunkNamespace)
            .reduce(0) { incrSize, data in
                incrSize + data.count
            }

        compacting = false
    }

    /// Save incremental changes of the existing Automerge document.
    /// - Parameters:
    ///   - id: The Id of the document
    ///   - doc: The automerge document
    public func saveIncremental(id: DocumentId, doc: Document) async throws {
        var chunkCollection = chunks[id] ?? []
        let oldHeads = latestHeads[id] ?? Set<ChangeHash>()
        let incrementalChanges = try doc.encodeChangesSince(heads: oldHeads)
        chunkCollection.append(incrementalChanges)
        chunks[id] = chunkCollection
        try await _storage.addToRange(id: id, prefix: chunkNamespace, data: incrementalChanges)
        latestHeads[id] = doc.heads()
    }

//    public func loadSyncState(id _: DocumentId, storageId _: SyncV1.STORAGE_ID) async -> SyncState {
//        SyncState()
//    }
//
//    public func saveSyncState(id _: DocumentId, storageId _: SyncV1.STORAGE_ID, state _: SyncState) async {}
}
