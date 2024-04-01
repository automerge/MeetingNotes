import Automerge
import AutomergeRepo
import Foundation
import OSLog
import Tracing

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

// Tracing experimentation
struct InMemoryNetworkMsgBaggageManipulator: Injector, Extractor {
    func inject(_ value: String, forKey key: String, into request: inout InMemoryNetworkMsg) {
        request.appendHeader(key: key, value: value)
    }

    func extract(key: String, from carrier: InMemoryNetworkMsg) -> String? {
        if let valueForKey = carrier.headers[key] {
            return valueForKey
        }
        return nil
    }
}

/// Emulates a protocol that supports headers or other embedded details
public struct InMemoryNetworkMsg: Sendable, CustomDebugStringConvertible {
    var headers: [String: String] = [:]
    var payload: SyncV1Msg

    public var debugDescription: String {
        var str = ""
        for (k, v) in headers {
            str.append("[\(k):\(v)]")
        }
        str.append(" - \(payload.debugDescription)")
        return str
    }

    init(headers: [String: String] = [:], _ payload: SyncV1Msg) {
        self.headers = headers
        self.payload = payload
    }

    mutating func appendHeader(key: String, value: String) {
        headers[key] = value
    }
}

@InMemoryNetwork
public final class InMemoryNetworkConnection {
    public var description: String {
        get async {
            let i = initiatingEndpoint.endpointName ?? "?"
            let j = receivingEndpoint.endpointName ?? "?"
            return "\(id.uuidString) [\(i)(\(initiatingEndpoint.peerId ?? "unconfigured"))] --> [\(j)(\(receivingEndpoint.peerId ?? "unconfigured"))])"
        }
    }

    let id: UUID
    let initiatingEndpoint: InMemoryNetworkEndpoint
    let receivingEndpoint: InMemoryNetworkEndpoint
    let transferLatency: Duration?
    let trace: Bool

    init(from: InMemoryNetworkEndpoint, to: InMemoryNetworkEndpoint, latency: Duration?, trace: Bool) {
        self.id = UUID()
        self.initiatingEndpoint = from
        self.receivingEndpoint = to
        self.transferLatency = latency
        self.trace = trace
    }

    func close() async {
        await self.initiatingEndpoint.connectionTerminated(self.id)
        await self.receivingEndpoint.connectionTerminated(self.id)
    }

    func send(sender: String, msg: InMemoryNetworkMsg) async {
        do {
            if initiatingEndpoint.endpointName == sender {
                if let latency = transferLatency {
                    try await Task.sleep(for: latency)
                    if trace {
                        Logger.testNetwork
                            .trace(
                                "XMIT[\(self.id.bs58String)] \(msg.debugDescription) from \(sender) with delay \(latency)"
                            )
                    }
                } else {
                    if trace {
                        Logger.testNetwork.trace("XMIT[\(self.id.bs58String)] \(msg.debugDescription) from \(sender)")
                    }
                }
                await receivingEndpoint.receiveMessage(msg: msg.payload)
            } else if receivingEndpoint.endpointName == sender {
                if let latency = transferLatency {
                    try await Task.sleep(for: latency)
                    if trace {
                        Logger.testNetwork
                            .trace(
                                "XMIT[\(self.id.bs58String)] \(msg.debugDescription) from \(sender) with delay \(latency)"
                            )
                    }
                } else {
                    if trace {
                        Logger.testNetwork.trace("XMIT[\(self.id.bs58String)] \(msg.debugDescription) from \(sender)")
                    }
                }
                await initiatingEndpoint.receiveMessage(msg: msg.payload)
            }
        } catch {
            Logger.testNetwork.error("Failure during latency sleep: \(error.localizedDescription)")
        }
    }
}

@InMemoryNetwork // isolate all calls to this class using the InMemoryNetwork global actor
public final class InMemoryNetworkEndpoint: NetworkProvider {
    public struct BasicNetworkConfiguration: Sendable {
        let listeningNetwork: Bool
        let name: String
    }

    init() {
        self.peeredConnections = []
        self._connections = []
        self.listening = false

        self.delegate = nil
        self.peerId = nil
        self.peerMetadata = nil

        // testing spies
        self.received_messages = []
        self.sent_messages = []
        // logging control
        self.logReceivedMessages = false
    }

    public func configure(_ config: BasicNetworkConfiguration) async {
        self.config = config
        if config.listeningNetwork {
            self.listening = true
        }
    }

    public var debugDescription: String {
        if let peerId = self.peerId {
            "In-Memory Network: \(peerId)"
        } else {
            "Unconfigured In-Memory Network"
        }
    }

    public var peeredConnections: [PeerConnection]
    var _connections: [InMemoryNetworkConnection]
    var delegate: (any NetworkEventReceiver)?
    var config: BasicNetworkConfiguration?
    var listening: Bool
    var logReceivedMessages: Bool

    public var peerId: PEER_ID?
    var peerMetadata: PeerMetadata?

    var received_messages: [SyncV1Msg]
    var sent_messages: [SyncV1Msg]

    func wipe() {
        self.peeredConnections = []
        self._connections = []
        self.received_messages = []
        self.sent_messages = []
    }

    public func logReceivedMessages(_ enableLogging: Bool) {
        self.logReceivedMessages = enableLogging
    }

    public var endpointName: String? {
        self.config?.name
    }

    public func acceptNewConnection(_ connection: InMemoryNetworkConnection) async {
        withSpan("accept-new-connection") { _ in
            if listening {
                self._connections.append(connection)
            } else {
                fatalError("Can't accept connection on a non-listening interface")
            }
        }
    }

    public func connectionTerminated(_ id: UUID) async {
        withSpan("connection-terminated") { _ in
            self._connections.removeAll { connection in
                connection.id == id
            }
        }
    }

    public func connect(to: String) async throws {
        guard let name = self.endpointName,
              let peerId = self.peerId,
              let peerMetadata = self.peerMetadata
        else {
            fatalError("Can't connect an unconfigured network")
        }
        // aka "activate"
        try await withSpan("connect") { span in

            let connection = try await InMemoryNetwork.shared.connect(from: name, to: to, latency: nil)

            self._connections.append(connection)

            let attributes: [String: SpanAttribute] = [
                "type": SpanAttribute(stringLiteral: "join"),
                "peerId": SpanAttribute(stringLiteral: peerId),
            ]

            span.addEvent(SpanEvent(name: "message send", attributes: SpanAttributes(attributes)))

            await connection.send(
                sender: name,

                msg: InMemoryNetworkMsg(
                    .join(.init(senderId: peerId, metadata: peerMetadata))
                )
            )
        }
    }

    public func disconnect() async {
        await withSpan("disconnect") { _ in
            for connection in _connections {
                await connection.close()
            }
            _connections = []
            peeredConnections = []
        }
    }

    func receiveWrappedMessage(msg: InMemoryNetworkMsg) async {
        await withSpan("receiveWrappedMessage") { _ in
            if var context = ServiceContext.current {
                InstrumentationSystem.instrument.extract(
                    msg,
                    into: &context,
                    using: InMemoryNetworkMsgBaggageManipulator()
                )
            }
            await self.receiveMessage(msg: msg.payload)
        }
    }

    public func receiveMessage(msg: SyncV1Msg) async {
        await withSpan("receiveWrappedMessage") { span in
            guard let peerId = self.peerId else {
                fatalError("Attempting to receive message with unconfigured network adapter")
            }
            if logReceivedMessages {
                Logger.testNetwork.trace("\(peerId) RECEIVED MSG: \(msg.debugDescription)")
            }
            received_messages.append(msg)
            switch msg {
            case let .leave(msg):
                span.addEvent(SpanEvent(name: "leave msg received"))
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
                    span.addEvent(SpanEvent(name: "join msg received"))
                    await self.delegate?.receiveEvent(
                        event: .peerCandidate(
                            payload: .init(
                                peerId: msg.senderId,
                                peerMetadata: msg.peerMetadata
                            )
                        )
                    )
                    peeredConnections.append(PeerConnection(peerId: msg.senderId, peerMetadata: msg.peerMetadata))
                    span.addEvent(SpanEvent(name: "replying with peer msg"))
                    await self.send(
                        message: .peer(
                            .init(
                                senderId: peerId,
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
                span.addEvent(SpanEvent(name: "peer msg received"))
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
                if self.delegate == nil, logReceivedMessages {
                    Logger.testNetwork
                        .warning("ADAPTER \(self.debugDescription) has no delegate, ignoring received message")
                }
                span.addEvent(SpanEvent(name: "forwarding received msg to delegate"))
                await self.delegate?.receiveEvent(event: .message(payload: msg))
            }
        }
    }

    public func send(message: SyncV1Msg, to: PEER_ID?) async {
        guard let endpointName = self.endpointName else {
            fatalError("Can't send without a configured endpoint")
        }
        await withSpan("send message") { span in
            sent_messages.append(message)

            var wrappedMsg = InMemoryNetworkMsg(message)
            if let context = ServiceContext.current {
                InstrumentationSystem.instrument.inject(
                    context,
                    into: &wrappedMsg,
                    using: InMemoryNetworkMsgBaggageManipulator()
                )
            }

            if let peerTarget = to {
                let connectionsWithPeer = _connections.filter { connection in
                    connection.initiatingEndpoint.peerId == peerTarget ||
                        connection.receivingEndpoint.peerId == peerTarget
                }
                for connection in connectionsWithPeer {
                    span.addEvent(
                        SpanEvent(name: "send message to peer", attributes: SpanAttributes([
                            "msg": SpanAttribute(stringLiteral: wrappedMsg.debugDescription),
                            "destination": SpanAttribute(stringLiteral: peerTarget),
                        ]))
                    )
                    await connection.send(sender: endpointName, msg: wrappedMsg)
                }
            } else {
                // broadcast
                for connection in _connections {
                    await connection.send(sender: endpointName, msg: wrappedMsg)
                }
            }
        }
    }

    public func setDelegate(
        _ delegate: any NetworkEventReceiver,
        as peer: PEER_ID,
        with metadata: AutomergeRepo.PeerMetadata?
    ) async {
        self.peerId = peer
        self.peerMetadata = metadata
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
    var enableTracing: Bool = false

    public func traceConnections(_ enableTracing: Bool) {
        self.enableTracing = enableTracing
    }

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

            let newConnection = await InMemoryNetworkConnection(
                from: initiator,
                to: destination,
                latency: latency,
                trace: self.enableTracing
            )
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
