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
// - impl is responsible for the setup and peering part of the handshake/state diagram
// beyond that, messages are passed up to the level above to deal with. In the Automerge-repo
// that's achieved by event emitters (equiv to the publisher concept in iOS)
//
// On the "making a connection" side of things, the connection is established to any relevant
// destinations, and a "ready" signal is sent out. After which, it sends a `join` message over the transport and await
// for future messages.
// When it receives a "peer" message, the `peerCandidate` is trigger up the event pipeline, otherwise the message itself
// is sent upwards. (error messages are just logged it seems)
// on a socket close, there's a `peerDisconnect` message propogated, and if a retry is set up, it'll retry to connect
// and stay established.
//
// There's a sender "leave" message sent just before disconnect:
// { type: "leave", senderId: this.peerId }
//
//
// On the receiving side, when a connection is opened the `ready` signal is emitted.
// When the receiver gets a 'join' message, it checks to see if it knows about the sender, and may send
// a peer-disconnected message and close that other channel, but generally emits a new `peerCandidate`
// message. It checks and if the protocol versions don't align, it'll send an error and close
// the connection.
// If it receives that "leave" message, it'll politely terminate the connection.
// Otherwise it takes the message and emits it upward for someone else to deal with.

/// A type that is responsible for establishing, and maintaining, a network connection for Automerge
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
