import AsyncAlgorithms

// import protocol Combine.Publisher
import Automerge

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
public protocol NetworkProvider<ProviderConfiguration>: Sendable {
    /// The peer Id of the local instance.
    var peerId: PEER_ID { get async }

    /// A list of all active, peered connections that the provider is maintaining.
    ///
    /// For an outgoing connection, this is typically a single connection.
    /// For a listening connection, this could be quite a few.
    var peeredConnections: [PeerConnection] { get async }

    /// The type used to configure an instance of a Network Provider.
    associatedtype ProviderConfiguration: Sendable

    /// For outgoing connections, the type that represents the endpoint to connect
    /// For example, it could be `URL`, `NWEndpoint` for a Bonjour network, or a custom type.
    associatedtype NetworkConnectionEndpoint: Sendable

    /// Configure the network provider.
    /// - Parameter _: the configuration for the network provider.
    ///
    /// After a NetworkProvider is configured, it is expected to have a local peerId and (optionally) peerMetaData.
    /// This can be provided in the initializer, or established with the `configure` call.
    ///
    /// For connecting providers, this may include enabling or disabling automatic reconnection,
    /// as well as relevant timeouts for connections.
    func configure(_ config: ProviderConfiguration) async

    /// Initiate an outgoing connection.
    func connect(to: NetworkConnectionEndpoint) async throws // aka "activate"

    /// Disconnect and terminate any existing connection.
    func disconnect() async // aka "deactivate"

    /// Requests the network transport to send a message.
    /// - Parameter message: The message to send.
    /// - Parameter to: An option peerId to identify the recipient for the message. If nil, the message is sent to all
    /// connected peers.
    func send(message: SyncV1Msg, to: PEER_ID?) async

    /// Called by a connection to process an event.
    /// - Parameter msg: The message to process.
    func receiveMessage(msg: SyncV1Msg) async

    /// Sets the delegate for a Network Provider
    /// - Parameter to: The instance that accepts asynchronous network events from the provider.
    func setDelegate(_ to: any NetworkEventReceiver) async
}

/// A type that accepts provides a method for a Network Provider to call with network events.
public protocol NetworkEventReceiver: Sendable {
    /// Receive and process an event from a Network Provider.
    /// - Parameter event: The event to process.
    func receiveEvent(event: NetworkAdapterEvents) async
}
