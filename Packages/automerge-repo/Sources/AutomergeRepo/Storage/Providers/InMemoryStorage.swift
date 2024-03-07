import struct Foundation.Data
import struct Foundation.UUID

/// An in-memory only storage provider.
public actor InMemoryStorage: StorageProvider {
    public nonisolated let id: SyncV1.STORAGE_ID = UUID().uuidString

    var _storage: [DocumentId: Data] = [:]
    var _incrementalChunks: [CombinedKey: [Data]] = [:]

    struct CombinedKey: Hashable {
        let id: DocumentId
        let prefix: String
    }

    public func load(key: DocumentId) async -> Data? {
        _storage[key]
    }

    public func save(key: DocumentId, data: Data) async {
        _storage[key] = data
    }

    public func remove(key: DocumentId) async {
        _storage.removeValue(forKey: key)
    }

    // MARK: Incremental Load Support

    public func addToRange(key: DocumentId, prefix: String, data: Data) async {
        var dataArray: [Data] = _incrementalChunks[CombinedKey(id: key, prefix: prefix)] ?? []
        dataArray.append(data)
        _incrementalChunks[CombinedKey(id: key, prefix: prefix)] = dataArray
    }

    public func loadRange(key: DocumentId, prefix: String) async -> [Data] {
        _incrementalChunks[CombinedKey(id: key, prefix: prefix)] ?? []
    }

    public func removeRange(key: DocumentId, prefix: String, data: [Data]) async {
        var chunksForKey: [Data] = _incrementalChunks[CombinedKey(id: key, prefix: prefix)] ?? []
        for d in data {
            if let indexToRemove = chunksForKey.firstIndex(of: d) {
                chunksForKey.remove(at: indexToRemove)
            }
        }
        _incrementalChunks[CombinedKey(id: key, prefix: prefix)] = chunksForKey
    }
}
