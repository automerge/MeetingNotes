import protocol Combine.Publisher
import struct Foundation.Data
import struct Foundation.UUID

public enum NetworkAdapterEvents {
    public struct OpenPayload {
        let network: any NetworkSyncProvider
    }

    public struct PeerCandidatePayload {
        let peerId: UUID
        let peerMetadata: SyncV1.PeerMetadata
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
public protocol NetworkSyncProvider<ProviderConfiguration> {
    var peerId: UUID { get }
    var peerMetadata: SyncV1.PeerMetadata { get }
    var connectedPeers: [UUID] { get }

    associatedtype ProviderConfiguration // network provider configuration
    func configure(_: ProviderConfiguration)

    func connect(asPeer: UUID, metadata: SyncV1.PeerMetadata?) async // aka "activate"
    func disconnect() async // aka "deactivate"

    func send(message: SyncV1) async
    associatedtype NetworkEvents: Publisher<NetworkAdapterEvents, Never>
    var eventPublisher: NetworkEvents { get }
}
