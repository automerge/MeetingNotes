import AutomergeRepo
import struct Foundation.Data
import struct Foundation.UUID

@globalActor public actor TestActor {
    public static var shared = TestActor()
}

/// An in-memory only storage provider.
@TestActor
public final class InMemoryStorage: StorageProvider {
    public nonisolated let id: STORAGE_ID = UUID().uuidString

    var _storage: [DocumentId: Data] = [:]
    var _incrementalChunks: [CombinedKey: [Data]] = [:]

    public init() {}

    public struct CombinedKey: Hashable, Comparable {
        public static func < (lhs: InMemoryStorage.CombinedKey, rhs: InMemoryStorage.CombinedKey) -> Bool {
            if lhs.prefix == rhs.prefix {
                return lhs.id < rhs.id
            }
            return lhs.prefix < rhs.prefix
        }

        public let id: DocumentId
        public let prefix: String
    }

    public func load(id: DocumentId) async -> Data? {
        _storage[id]
    }

    public func save(id: DocumentId, data: Data) async {
        _storage[id] = data
    }

    public func remove(id: DocumentId) async {
        _storage.removeValue(forKey: id)
    }

    // MARK: Incremental Load Support

    public func addToRange(id: DocumentId, prefix: String, data: Data) async {
        var dataArray: [Data] = _incrementalChunks[CombinedKey(id: id, prefix: prefix)] ?? []
        dataArray.append(data)
        _incrementalChunks[CombinedKey(id: id, prefix: prefix)] = dataArray
    }

    public func loadRange(id: DocumentId, prefix: String) async -> [Data] {
        _incrementalChunks[CombinedKey(id: id, prefix: prefix)] ?? []
    }

    public func removeRange(id: DocumentId, prefix: String, data: [Data]) async {
        var chunksForKey: [Data] = _incrementalChunks[CombinedKey(id: id, prefix: prefix)] ?? []
        for d in data {
            if let indexToRemove = chunksForKey.firstIndex(of: d) {
                chunksForKey.remove(at: indexToRemove)
            }
        }
        _incrementalChunks[CombinedKey(id: id, prefix: prefix)] = chunksForKey
    }

    // MARK: Testing Spies/Support

    public func storageKeys() -> [DocumentId] {
        _storage.keys.sorted()
    }

    public func incrementalKeys() -> [CombinedKey] {
        _incrementalChunks.keys.sorted()
    }
}
