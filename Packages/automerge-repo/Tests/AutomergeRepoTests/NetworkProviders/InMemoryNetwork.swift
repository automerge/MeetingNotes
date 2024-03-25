import Automerge
import AutomergeRepo
import Foundation
import OSLog

extension Logger {
    static let testNetwork = Logger(subsystem: "InMemoryNetwork", category: "testNetwork")
}

enum InMemoryNetworkErrors: Sendable {
    public struct NoSuchEndpoint: Sendable, LocalizedError {
        let name: String
        public var errorDescription: String {
            "Endpoint \(name) doesn't exist."
        }
    }

    public struct EndpointNotListening: Sendable, LocalizedError {
        let name: String
        public var errorDescription: String {
            "Endpoint \(name) isn't listening for connections."
        }
    }
}

@InMemoryNetwork
public final class InMemoryNetworkConnection {
    public var description: String { get async {
        let i = initiatingEndpoint.endpointName ?? "?"
        let j = receivingEndpoint.endpointName ?? "?'"
        return "\(id.uuidString) [\(i)(\(initiatingEndpoint.peerId))] --> [\(j)(\(receivingEndpoint.peerId))])"
    }
    }

    let id: UUID
    let initiatingEndpoint: InMemoryNetworkEndpoint
    let receivingEndpoint: InMemoryNetworkEndpoint
    let transferLatency: Duration?

    init(from: InMemoryNetworkEndpoint, to: InMemoryNetworkEndpoint, latency: Duration?) {
        self.id = UUID()
        self.initiatingEndpoint = from
        self.receivingEndpoint = to
        self.transferLatency = latency
    }

    func close() async {
        await self.initiatingEndpoint.connectionTerminated(self.id)
        await self.receivingEndpoint.connectionTerminated(self.id)
    }

    func send(sender: String, msg: SyncV1Msg) async {
        do {
            if initiatingEndpoint.endpointName == sender {
                if let latency = transferLatency {
                    try await Task.sleep(for: latency)
                }
                await receivingEndpoint.receiveMessage(msg: msg)
            } else if receivingEndpoint.endpointName == sender {
                await initiatingEndpoint.receiveMessage(msg: msg)
            }
        } catch {
            Logger.testNetwork.error("Failure during latency sleep: \(error.localizedDescription)")
        }
    }
}

@InMemoryNetwork // isolate all calls to this class using the InMemoryNetwork global actor
public final class InMemoryNetworkEndpoint: NetworkProvider {
    public struct BasicNetworkConfiguration: Sendable {
        let localPeerId: PEER_ID
        let localMetaData: PeerMetadata?
        let listeningNetwork: Bool
        let name: String
    }

    init() {
        self.peeredConnections = []
        self._connections = []
        self.delegate = nil
        self.listening = false

        // testing spies
        self.received_messages = []
        self.sent_messages = []
    }

    public func configure(_ config: BasicNetworkConfiguration) async {
        self.config = config
        if config.listeningNetwork {
            self.listening = true
        }
    }

    public var debugDescription: String {
        if let config = self.config {
            "In-Memory Network: \(config.localPeerId)"
        } else {
            "Unconfigured In-Memory Network"
        }
    }

    public var peeredConnections: [PeerConnection]
    var _connections: [InMemoryNetworkConnection]
    var delegate: (any NetworkEventReceiver)?
    var config: BasicNetworkConfiguration?
    var listening: Bool

    var received_messages: [SyncV1Msg]
    var sent_messages: [SyncV1Msg]

    func wipe() {
        self.peeredConnections = []
        self._connections = []
        self.received_messages = []
        self.sent_messages = []
    }

    public var peerId: PEER_ID {
        self.config?.localPeerId ?? "UNCONFIGURED"
    }

    public var peerMetadata: PeerMetadata? {
        self.config?.localMetaData
    }

    public var endpointName: String? {
        self.config?.name
    }

    public func acceptNewConnection(_ connection: InMemoryNetworkConnection) async {
        if listening {
            self._connections.append(connection)
        } else {
            fatalError("Can't accept connection on a non-listening interface")
        }
    }

    public func connectionTerminated(_ id: UUID) async {
        self._connections.removeAll { connection in
            connection.id == id
        }
    }

    public func connect(to: String) async throws {
        guard let name = self.endpointName else {
            fatalError("Can't connect an unconfigured network")
        }
        // aka "activate"
        let connection = try await InMemoryNetwork.shared.connect(from: name, to: to, latency: nil)
        self._connections.append(connection)
        await connection.send(sender: name, msg: .join(
            .init(senderId: self.peerId, metadata: self.peerMetadata)
        ))
    }

    public func disconnect() async {
        for connection in _connections {
            await connection.close()
        }
        _connections = []
        peeredConnections = []
    }

    public func receiveMessage(msg: SyncV1Msg) async {
        Logger.testNetwork.trace("\(self.peerId) RECEIVED MSG: \(msg.debugDescription)")
        received_messages.append(msg)
        switch msg {
        case let .leave(msg):
            await self.delegate?.receiveEvent(event: .close)
            _connections.removeAll { connection in
                connection.initiatingEndpoint.peerId == msg.senderId ||
                    connection.receivingEndpoint.peerId == msg.senderId
            }
            peeredConnections.removeAll { peerConnection in
                peerConnection.peerId == msg.senderId
            }
        case let .join(msg):
            if listening {
                await self.delegate?.receiveEvent(
                    event: .peerCandidate(
                        payload: .init(
                            peerId: msg.senderId,
                            peerMetadata: msg.peerMetadata
                        )
                    )
                )
                peeredConnections.append(PeerConnection(peerId: msg.senderId, peerMetadata: msg.peerMetadata))
                await self.send(
                    message: .peer(
                        .init(
                            senderId: self.peerId,
                            targetId: msg.senderId,
                            storageId: self.peerMetadata?.storageId,
                            ephemeral: self.peerMetadata?.isEphemeral ?? true
                        )
                    ),
                    to: msg.senderId
                )
            } else {
                fatalError("non-listening endpoint received a join message")
            }
        case let .peer(msg):
            peeredConnections.append(PeerConnection(peerId: msg.senderId, peerMetadata: msg.peerMetadata))
            await self.delegate?.receiveEvent(
                event: .ready(
                    payload: .init(
                        peerId: msg.senderId,
                        peerMetadata: msg.peerMetadata
                    )
                )
            )
        default:
            await self.delegate?.receiveEvent(event: .message(payload: msg))
        }
    }

    public func send(message: SyncV1Msg, to: PEER_ID?) async {
        guard let endpointName = self.endpointName else {
            fatalError("Can't send without a configured endpoint")
        }
        sent_messages.append(message)
        if let peerTarget = to {
            let connectionsWithPeer = _connections.filter { connection in
                connection.initiatingEndpoint.peerId == peerTarget ||
                    connection.receivingEndpoint.peerId == peerTarget
            }
            for connection in connectionsWithPeer {
                await connection.send(sender: endpointName, msg: message)
            }
        } else {
            // broadcast
            for connection in _connections {
                await connection.send(sender: endpointName, msg: message)
            }
        }
    }

    public func setDelegate(_ delegate: any NetworkEventReceiver) async {
        self.delegate = delegate
    }
}

/// A Test network that operates in memory
///
/// Acts akin to an outbound connection - doesn't "connect" and trigger messages until you explicitly ask
@globalActor public actor InMemoryNetwork {
    public static let shared = InMemoryNetwork()

    private init() {}
    var endpoints: [String: InMemoryNetworkEndpoint] = [:]
    var simulatedConnections: [InMemoryNetworkConnection] = []

    public func networkEndpoint(named: String) -> InMemoryNetworkEndpoint? {
        let x = endpoints[named]
        return x
    }

    public func connections() -> [InMemoryNetworkConnection] {
        simulatedConnections
    }

    // MARK: TESTING SPECIFIC API

    public func createNetworkEndpoint(
        config: InMemoryNetworkEndpoint.BasicNetworkConfiguration
    ) async -> InMemoryNetworkEndpoint {
        let x = await InMemoryNetworkEndpoint()
        endpoints[config.name] = x
        await x.configure(config)
        return x
    }

    public func connect(from: String, to: String, latency: Duration?) async throws -> InMemoryNetworkConnection {
        if let initiator = networkEndpoint(named: from), let destination = networkEndpoint(named: to) {
            guard await destination.listening == true else {
                throw InMemoryNetworkErrors.EndpointNotListening(name: to)
            }

            let newConnection = await InMemoryNetworkConnection(from: initiator, to: destination, latency: latency)
            simulatedConnections.append(newConnection)
            await destination.acceptNewConnection(newConnection)
            return newConnection
        } else {
            throw InMemoryNetworkErrors.NoSuchEndpoint(name: to)
        }
    }

    public func terminateConnection(_ id: UUID) async {
        if let connectionIndex = simulatedConnections.firstIndex(where: { $0.id == id }) {
            let connection = simulatedConnections[connectionIndex]
            await connection.close()
            simulatedConnections.remove(at: connectionIndex)
        }
    }

    public func messagesReceivedBy(name: String) async -> [SyncV1Msg] {
        if let msgs = await self.endpoints[name]?.received_messages {
            msgs
        } else {
            []
        }
    }

    public func messagesSentBy(name: String) async -> [SyncV1Msg] {
        if let msgs = await self.endpoints[name]?.sent_messages {
            msgs
        } else {
            []
        }
    }

    /// WIPES TEST NETWORK and resets all connections, but leaves endpoints intact and configured
    public func resetTestNetwork() async {
        for endpoint in self.endpoints.values {
            await endpoint.wipe()
        }
        endpoints.removeAll()

        for connection in simulatedConnections {
            await connection.close()
        }
        simulatedConnections = []
    }
}
