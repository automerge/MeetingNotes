// import protocol Combine.Publisher

import AsyncAlgorithms

// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkAdapterInterface.ts

/// A type that is responsible for establishing, and maintaining, a network connection for Automerge
///
/// Types conforming to this protocol are responsible for the setup and initial handshake with other
/// peers, and flow through messages to component that owns the reference to the network adapter.
/// A higher level object is responsible for responding to sync, gossip, and other messages appropriately.
///
/// A NetworkProvider instance can be either initiating or listening for - and responding to - a connection.
///
/// The expected behavior when a network provide initiates a connection:
///
/// - After the underlying transport connection is established due to a call to `connect`, the provider emits
/// ``NetworkAdapterEvents/ready(payload:)``, which includes a payload that indicates a
/// reference to the network provider (`any NetworkAdapter`).
/// - After the connection is established, the adapter sends a ``SyncV1/join(_:)`` message to request peering.
/// - When the NetworkAdapter receives a ``SyncV1/peer(_:)`` message, it emits
/// ``NetworkAdapterEvents/peerCandidate(payload:)``.
/// - If a message other than `peer` is received, the adapter should terminate the connection and emit
/// ``NetworkAdapterEvents/close``.
/// - All other messages are emitted as ``NetworkAdapterEvents/message(payload:)``.
/// - When a transport connection is closed, the adapter should emit ``NetworkAdapterEvents/peerDisconnect(payload:)``.
/// - When `disconnect` is invoked on a network provider, it should send a ``SyncV1/leave(_:)`` message, terminate the
/// connection, and emit ``NetworkAdapterEvents/close``.
///
/// A connecting transport may optionally enable automatic reconnection on connection failure. Any configurable
/// reconnection logic exists,
/// it should be configured with a `configure` call with the relevant configuration type for the network provider.
///
/// The expected behavior when listening for, and responding to, an incoming connection:
/// - When a connection is established, emit ``NetworkAdapterEvents/ready(payload:)``.
/// - When the transport receives a `join` message, verify that the protocols being requested are compatible. If they
/// are not,
/// return an ``SyncV1/error(_:)`` message, close the connection, and emit ``NetworkAdapterEvents/close``.
/// - When any other message is received, it is emitted with ``NetworkAdapterEvents/message(payload:)``.
/// - When the transport receives a `leave` message, close the connection and emit ``NetworkAdapterEvents/close``.
public protocol NetworkProvider<ProviderConfiguration>: Sendable, Identifiable {
    /// The identity of the network provider
    var id: PEER_ID { get }
    /// The peer Id of the local instance.
    var peerId: PEER_ID { get }
    /// The optional metadata associated with this peer's presentation.
    var peerMetadata: PeerMetadata? { get }
    /// The peer Id of the remote
    var connectedPeer: PEER_ID { get }

    /// The type used to configure an instance of a Network Provider.
    associatedtype ProviderConfiguration

    /// Configure the network provider.
    ///
    /// For connecting providers, this may include enabling automatic reconnection, as well as relevant timeouts for
    /// connections.
    /// - Parameter _: the configuration for the network provider.
    func configure(_: ProviderConfiguration)

    /// Initiate a connection.
    func connect(asPeer: PEER_ID, metadata: PeerMetadata?) async // aka "activate"

    /// Disconnect and terminate any existing connection.
    func disconnect() async // aka "deactivate"

    func ready() async -> Bool

    /// Sends a message.
    /// - Parameter message: The message to send.
    func send(message: SyncV1Msg) async

    /// A publisher that provides events and messages from the network provider.
    // Type 'NetworkAdapterEvents' does not conform to the 'Sendable' protocol
    var events: AsyncChannel<NetworkAdapterEvents> { get }

    // Combine version...
    // associatedtype NetworkEvents: Publisher<NetworkAdapterEvents, Never>
    // var eventPublisher: NetworkEvents { get }
}
