import Foundation
import Automerge
import Combine

protocol Synchronizer {
    var peerId: UUID { get }
    // publisher of some form for events? - e.g. event stream of Ephemeral messages
}

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
    
    public func loadDoc(id: DocumentId) async -> Document {
        return Document()
    }
    public func saveDoc(id: DocumentId, doc: Document) async { }
   
    public func compact(id: DocumentId, doc: Document, chunks: [Data]) async { }
    public func saveIncremental(id: DocumentId, doc: Document) async { }
   
    public func loadSyncState(id: DocumentId, storageId: UUID) async -> SyncState {
        return SyncState()
    }
    public func saveSyncState(id: DocumentId, storageId: UUID, state: SyncState) async { }
}

public struct PeerMetadata {
    var storageId: UUID?
    var isEphemeral: Bool
}

public enum NetworkAdapterEvents {
    public struct OpenPayload {
        let network: any NetworkSyncProvider
    }
    
    public struct PeerCandidatePayload {
        let peerId: UUID
        let peerMetadata: PeerMetadata
    }
    public struct PeerDisconnectPayload {
        let peerId: UUID
    }

    case ready(payload: OpenPayload)
    case close
    case peerCandidate(payload: PeerCandidatePayload)
    case peerDisconnect(payload: PeerDisconnectPayload)
    case message(payload: Data)
}
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkAdapterInterface.ts
public protocol NetworkSyncProvider<T> {
    associatedtype T // network provider configuration
    var peerId: UUID { get }
    var peerMetadata: PeerMetadata { get }
    var connectedPeers: UUID { get }
    
    func connect(asPeer: UUID, metadata: PeerMetadata?) async // aka "activate"
    func send(message: V1) async
    func disconnect() async // aka "deactivate"
    
    func configure(_: T)
    
    var eventPublisher: AnyPublisher<NetworkAdapterEvents, Never> { get }
}

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts
public struct NetworkSubsystem {
    var adapters: [any NetworkSyncProvider]
    
    init(adapters: [any NetworkSyncProvider]) {
        self.adapters = adapters
    }
    
    func send(message: Data) { }
    func isReady() async -> Bool {
        return false
    }
    func whenReady() async { }
    
    let eventPublisher: PassthroughSubject<NetworkAdapterEvents, Never> = PassthroughSubject()
}
