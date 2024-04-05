import OSLog

public actor WebSocketProvider: NetworkProvider {
    public typealias ProviderConfiguration = WebSocketProviderConfiguration
    public struct WebSocketProviderConfiguration: Sendable {
        let reconnectOnError: Bool

        public static let `default` = WebSocketProviderConfiguration(reconnectOnError: true)
    }

    public var peeredConnections: [PeerConnection]
    var delegate: (any NetworkEventReceiver)?
    var peerId: PEER_ID?
    var peerMetadata: PeerMetadata?
    var webSocketTask: URLSessionWebSocketTask?
    var backgroundWebSocketReceiveTask: Task<Void, any Error>?
    var config: WebSocketProviderConfiguration
    var endpoint: URL?

    public init(_ config: WebSocketProviderConfiguration = .default) {
        self.config = config
        self.peeredConnections = []
        self.delegate = nil
        self.peerId = nil
        self.peerMetadata = nil
        self.webSocketTask = nil
        self.backgroundWebSocketReceiveTask = nil
    }

    // MARK: NetworkProvider Methods

    public func connect(to url: URL) async throws {
        // TODO: refactor the connection logic to separate connecting and handling the peer/join
        // messaging, from setting up the ongoing looping to allow for multiple retry attempts
        // that return a concrete value of "good/no-good" separate from a protocol failure.
        //  ... something like
        // func attemptConnect(to url: URL) async throws -> URLSessionWebSocketTask?
        guard let peerId = self.peerId,
              let delegate = self.delegate
        else {
            fatalError("Attempting to connect before connected to a delegate")
        }

        // establish the WebSocket connection
        self.endpoint = url
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        guard let webSocketTask else {
            #if DEBUG
            fatalError("Attempting to configure and join a nil webSocketTask")
            #else
            return
            #endif
        }

        Logger.webSocket.trace("Activating websocket to \(url, privacy: .public)")
        // start the websocket processing things
        webSocketTask.resume()

        // since we initiated the WebSocket, it's on us to send an initial 'join'
        // protocol message to start the handshake phase of the protocol
        let joinMessage = SyncV1Msg.JoinMsg(senderId: peerId, metadata: self.peerMetadata)
        let data = try SyncV1Msg.encode(joinMessage)
        try await webSocketTask.send(.data(data))
        Logger.webSocket.trace("SEND: \(joinMessage.debugDescription)")

        do {
            // Race a timeout against receiving a Peer message from the other side
            // of the WebSocket connection. If we fail that race, shut down the connection
            // and move into a .closed connectionState
            let websocketMsg = try await self.nextMessage(withTimeout: .seconds(3.5))

            // Now that we have the WebSocket message, figure out if we got what we expected.
            // For the sync protocol handshake phase, it's essentially "peer or die" since
            // we were the initiating side of the connection.
            guard case let .peer(peerMsg) = try attemptToDecode(websocketMsg, peerOnly: true) else {
                throw SyncV1Msg.Errors.UnexpectedMsg(msg: websocketMsg)
            }
            let newPeerConnection = PeerConnection(peerId: peerMsg.senderId, peerMetadata: peerMsg.peerMetadata)
            self.peeredConnections = [newPeerConnection]
            await delegate.receiveEvent(event: .ready(payload: newPeerConnection))
            Logger.webSocket.trace("Peered to targetId: \(peerMsg.senderId) \(peerMsg.debugDescription)")
        } catch {
            // if there's an error, disconnect anything that's lingering and cancel it down.
            await self.disconnect()
            throw error
        }

        // If we have an existing task there, looping over messages, it means there was
        // one previously set up, and there was a connection failure - at which point
        // a reconnect was created to re-establish the webSocketTask.
        if self.backgroundWebSocketReceiveTask == nil {
            // infinitely loop and receive messages, but "out of band"
            backgroundWebSocketReceiveTask = Task.detached {
                try await self.ongoingRecieveWebSocketMessage()
            }
        }
    }

    public func disconnect() async {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        self.webSocketTask = nil
        self.backgroundWebSocketReceiveTask?.cancel()
        self.backgroundWebSocketReceiveTask = nil
        self.endpoint = nil

        if let connectedPeer = self.peeredConnections.first {
            self.peeredConnections.removeAll()
            await delegate?.receiveEvent(event: .peerDisconnect(payload: .init(peerId: connectedPeer.peerId)))
        }

        await delegate?.receiveEvent(event: .close)
    }

    public func send(message: SyncV1Msg, to _: PEER_ID?) async {
        guard let webSocketTask = self.webSocketTask else {
            Logger.webSocket.warning("Attempt to send a message without a connection")
            return
        }

        do {
            let data = try SyncV1Msg.encode(message)
            try await webSocketTask.send(.data(data))
        } catch {
            Logger.webSocket.error("Unable to encode and send message: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func setDelegate(
        _ delegate: any NetworkEventReceiver,
        as peer: PEER_ID,
        with metadata: PeerMetadata?
    ) async {
        self.delegate = delegate
        self.peerId = peer
        self.peerMetadata = metadata
    }

    // MARK: utility methods

    private func attemptToDecode(_ msg: URLSessionWebSocketTask.Message, peerOnly: Bool = false) throws -> SyncV1Msg {
        // Now that we have the WebSocket message, figure out if we got what we expected.
        // For the sync protocol handshake phase, it's essentially "peer or die" since
        // we were the initiating side of the connection.
        switch msg {
        case let .data(raw_data):
            if peerOnly {
                let msg = SyncV1Msg.decodePeer(raw_data)
                if case .peer = msg {
                    return msg
                } else {
                    // In the handshake phase and received anything other than a valid peer message
                    let decodeAttempted = SyncV1Msg.decode(raw_data)
                    Logger.webSocket
                        .warning(
                            "Decoding websocket message, expecting peer only - and it wasn't a peer message. RECEIVED MSG: \(decodeAttempted.debugDescription)"
                        )
                    throw SyncV1Msg.Errors.UnexpectedMsg(msg: decodeAttempted)
                }
            } else {
                let decodedMsg = SyncV1Msg.decode(raw_data)
                if case .unknown = decodedMsg {
                    throw SyncV1Msg.Errors.UnexpectedMsg(msg: decodedMsg)
                }
                return decodedMsg
            }

        case let .string(string):
            // In the handshake phase and received anything other than a valid peer message
            Logger.webSocket
                .warning("Unknown websocket message received: .string(\(string))")
            throw SyncV1Msg.Errors.UnexpectedMsg(msg: msg)
        @unknown default:
            // In the handshake phase and received anything other than a valid peer message
            Logger.webSocket
                .error("Unknown websocket message received: \(String(describing: msg))")
            throw SyncV1Msg.Errors.UnexpectedMsg(msg: msg)
        }
    }

    // throw error on timeout
    // throw error on cancel
    // otherwise return the msg
    private func nextMessage(
        withTimeout: ContinuousClock.Instant
            .Duration = .seconds(3.5)
    ) async throws -> URLSessionWebSocketTask.Message {
        // Co-operatively check to see if we're cancelled, and if so - we can bail out before
        // going into the receive loop.
        try Task.checkCancellation()

        // check the invariants
        guard let webSocketTask = self.webSocketTask
        else {
            throw SyncV1Msg.Errors
                .ConnectionClosed(errorDescription: "Attempting to wait for a websocket message when the task is nil")
        }

        // Race a timeout against receiving a Peer message from the other side
        // of the WebSocket connection. If we fail that race, shut down the connection
        // and move into a .closed connectionState
        let websocketMsg = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                // retrieve the next websocket message
                try await webSocketTask.receive()
            }

            group.addTask {
                // Race against the receive call with a continuous timer
                try await Task.sleep(for: withTimeout)
                throw SyncV1Msg.Errors.Timeout()
            }

            guard let msg = try await group.next() else {
                throw CancellationError()
            }
            // cancel all ongoing tasks (the websocket receive request, in this case)
            group.cancelAll()
            return msg
        }
        return websocketMsg
    }

    /// Infinitely loops over incoming messages from the websocket and updates the state machine based on the messages
    /// received.
    private func ongoingRecieveWebSocketMessage() async throws {
        var msgFromWebSocket: URLSessionWebSocketTask.Message?
        while true {
            guard let webSocketTask = self.webSocketTask else {
                Logger.webSocket.warning("Receive Handler: webSocketTask is nil, terminating handler loop")
                break
            }

            try Task.checkCancellation()

            do {
                msgFromWebSocket = try await webSocketTask.receive()
            } catch {
                if self.config.reconnectOnError, let endpoint = self.endpoint {
                    // TODO: add in some jitter/backoff logic, and potentially refactor to attempt to retry multiple times
                    try await self.connect(to: endpoint)
                } else {
                    throw error
                }
            }

            do {
                if let encodedMessage = msgFromWebSocket {
                    let msg = try attemptToDecode(encodedMessage)
                    await self.handleMessage(msg: msg)
                }
            } catch {
                // catch decode failures, but don't terminate the whole shebang
                // on a failure
                Logger.webSocket
                    .warning("Unable to decode websocket message: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func handleMessage(msg: SyncV1Msg) async {
        switch msg {
        case let .leave(msg):
            Logger.webSocket.trace("\(msg.senderId) requests to kill the connection")
            await self.disconnect()
        case let .join(msg):
            Logger.webSocket.error("Unexpected message received: \(msg.debugDescription)")
        case let .peer(msg):
            Logger.webSocket.error("Unexpected message received: \(msg.debugDescription)")
        default:
            await self.delegate?.receiveEvent(event: .message(payload: msg))
        }
    }
}
