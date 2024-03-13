import Automerge
import Combine
import Foundation
import OSLog
import PotentCBOR

/// A class that provides a WebSocket connection to sync an Automerge document.
@MainActor
public final class WebsocketSyncConnection: ObservableObject, Identifiable {
    private var webSocketTask: URLSessionWebSocketTask?
    /// This connections "peer identifier"
    private let senderId: String
    /// The peer identifier for the receiving end of the websocket.
    private var targetId: String? = nil

    private var syncState: Automerge.SyncState
    /// The Automerge document that this connection interacts with
    private weak var document: Automerge.Document?
    /// The identifier for this Automerge document
    private var documentId: DocumentId?

    /// A handle on an unstructured task that accepts and processes WebSocket messages
    private var receiveHandler: Task<Void, any Error>?

    /// A handle to a cancellable Combine pipeline that watches a document for updates and attempts to start a sync when
    /// it changes.
    private var syncTrigger: (any Cancellable)?

    // TODO: Add a delegate link of some form for a 'ephemeral' msg data handler
    // TODO: Add an indicator of if we should involve ourselves in "gossip" about updates

    @Published public var protocolState: ProtocolState
    @Published public var syncInProgress: Bool

    // MARK: Initializers, registration/setup

    // having register after initialization lets us add within a SwiftUI view, and then
    // configure and activate things onAppear within the view...
    public init(_ document: Automerge.Document?, id documentId: DocumentId?) {
        protocolState = .setup
        syncState = SyncState()
        senderId = UUID().uuidString
        self.document = document
        self.documentId = documentId
        self.syncInProgress = false
    }

    // having register after initialization lets us add within a SwiftUI view, and then
    // configure and activate things onAppear within the view...
    public func registerDocument(_ document: Automerge.Document, id: DocumentId) {
        self.document = document
        self.documentId = id
    }

    // MARK: static initializers

    public static func syncDocument(
        _ document: Automerge.Document,
        id: DocumentId,
        to destination: String
    ) async throws -> WebsocketSyncConnection {
        let websocketconnection = WebsocketSyncConnection(document, id: id)

        try await websocketconnection.connect(destination)
        try await websocketconnection.runOngoingSync()
        return websocketconnection
    }

    public static func requestDocument(
        _ id: DocumentId,
        from destination: String,
        setupOngoingSync: Bool = false
    ) async throws -> (Automerge.Document, WebsocketSyncConnection)? {
        let tempDocument = Document()

        let websocketconnection = WebsocketSyncConnection(tempDocument, id: id)

        assert(id == websocketconnection.documentId!)
        try await websocketconnection.connect(destination)

        try Task.checkCancellation()

        guard websocketconnection.protocolState == .ready else { return nil }

        // enable the request...
        websocketconnection.receiveHandler = nil
        try await websocketconnection.sendRequestForDocument()

        assert(websocketconnection.syncInProgress == true)

        while websocketconnection.syncInProgress {
            try Task.checkCancellation()
            Logger.webSocket
                .trace(
                    "sync in progress, !cancelled - state is: \(websocketconnection.protocolState.rawValue, privacy: .public)"
                )
            // Race a timeout against receiving a Peer message from the other side
            // of the WebSocket connection. If we fail that race, shut down the connection
            // and move into a .closed connectionState
            let websocketMsg = try await websocketconnection.nextMessage(withTimeout: .seconds(3.5))
            let decodedMsg = try websocketconnection.attemptToDecode(websocketMsg, peerOnly: false)
            await websocketconnection.handleReceivedMessage(msg: decodedMsg)
        }

        try Task.checkCancellation()

        if setupOngoingSync {
            // fire up an ongoing process to maintain synchronization
            websocketconnection.receiveHandler = Task {
                try await websocketconnection.ongoingHandleWebSocketMessage()
            }
            await websocketconnection.initiateSync()
        }

        return (tempDocument, websocketconnection)
    }

    // MARK: - Utility functions for stitching together async workflows of tasks

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

    // MARK: Connect

    /// Initiates a WebSocket connection to a remote peer.
    ///
    /// throws an error if something is awry, otherwise returns Void, with the connection established
    public func connect(_ destination: String) async throws {
        guard protocolState == .setup || protocolState == .closed else {
            return
        }
        guard self.document != nil, self.documentId != nil else {
            #if DEBUG
            fatalError("Attempting to join a connection without a document registered")
            #else
            Logger.webSocket.error("Attempting to join a connection without a document registered")
            return
            #endif
        }
        guard let url = URL(string: destination) else {
            Logger.webSocket.error("Destination provided is not a valid URL")
            throw SyncV1Msg.Errors.InvalidURL(urlString: destination)
        }

        // establishes the websocket
        let request = URLRequest(url: url)
        await MainActor.run {
            // reset the document's synchronization state maintained by the connection
            syncState = SyncState()
            webSocketTask = URLSession.shared.webSocketTask(with: request)
        }
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
        let joinMessage = SyncV1Msg.JoinMsg(senderId: senderId)
        let data = try SyncV1Msg.encode(joinMessage)
        try await webSocketTask.send(.data(data))
        Logger.webSocket.trace("SEND: \(joinMessage.debugDescription)")
        await MainActor.run {
            self.protocolState = .preparing
        }

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

            Logger.webSocket.trace("Peered to targetId: \(peerMsg.senderId) \(peerMsg.debugDescription)")
            // TODO: handle the gossip setup - read and process the peer metadata
            await MainActor.run {
                self.targetId = peerMsg.senderId
                self.protocolState = .ready
            }
        } catch {
            // if there's an error, disconnect anything that's lingering and cancel it down.
            await self.disconnect()
            throw error
        }
        assert(self.protocolState == .ready)
    }

    /// Asynchronously disconnect the WebSocket and shut down active sessions.
    public func disconnect() async {
        self.syncTrigger?.cancel()
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        self.receiveHandler?.cancel()
        await MainActor.run {
            self.syncTrigger = nil
            self.protocolState = .closed
            self.webSocketTask = nil
            self.syncInProgress = false
        }
    }

    public func runOngoingSync() async throws {
        // Co-operatively check to see if we're cancelled, and if so - we can bail out before
        // going into the receive loop.
        try Task.checkCancellation()

        // verify we're in the right state before invoking the recursive (async) handler setup
        // and start the process of synchronizing the document.
        if self.protocolState == .ready {
            // NOTE: this is technically a race between do we accept a message and do something
            // with it (possibly changing state), or do we initiate a sync ourselves. In practice
            // against Automerge-repo code, it doesn't proactively ask us to do anything, playing
            // a more reactive role, but it's worth being away its a possibility.
            self.receiveHandler = Task {
                try await ongoingHandleWebSocketMessage()
            }

            // kick off an initial sync
            await initiateSync()

            // Watch the Automerge document for update messages, triggering a sync
            // if one isn't already in flight.
            self.syncTrigger = self.document?.objectWillChange.sink {
                if !self.syncInProgress {
                    Task { [weak self] in
                        await self?.initiateSync()
                    }
                }
            }
        }
    }

    public func sendRequestForDocument() async throws {
        // verify we're already connected and peered
        guard protocolState == .ready,
              let document = self.document,
              let documentId = self.documentId,
              let targetId = self.targetId,
              let webSocketTask = self.webSocketTask,
              let syncData = document.generateSyncMessage(state: self.syncState)
        else {
            Logger.webSocket.warning("Attempting to join a connection without a document identifier registered")
            return
        }
        assert(
            // should be assured by the state diagram, but just in case.
            self.document != nil && self
                .documentId != nil
        )
        await MainActor.run {
            self.syncInProgress = true
        }
        let requestMsg = SyncV1Msg.RequestMsg(
            documentId: documentId.description,
            senderId: self.senderId,
            targetId: targetId,
            sync_message: syncData
        )
        let data = try SyncV1Msg.encode(requestMsg)
        try await webSocketTask.send(.data(data))
        Logger.webSocket.trace("SEND: \(requestMsg.debugDescription)")
    }

    /// Start a synchronization process for the Automerge document
    private func initiateSync() async {
        guard protocolState == .ready,
              syncInProgress == false
        else {
            return
        }
        guard let document = self.document,
              let documentId = self.documentId,
              let targetId = self.targetId,
              let webSocketTask = self.webSocketTask
        else {
            Logger.webSocket.warning("Attempting to join a connection without a document identifier registered")
            return
        }
        assert(
            // should be assured by the state diagram, but just in case.
            self.document != nil && self
                .documentId != nil
        )

        if let syncData = document.generateSyncMessage(state: self.syncState) {
            await MainActor.run {
                self.protocolState = .ready
                self.syncInProgress = true
            }
            let syncMsg = SyncV1Msg.SyncMsg(
                documentId: documentId.description,
                senderId: self.senderId,
                targetId: targetId,
                sync_message: syncData
            )
            var data: Data? = nil
            do {
                data = try SyncV1Msg.encode(syncMsg)
            } catch {
                Logger.webSocket.warning("Error encoding data: \(error.localizedDescription, privacy: .public)")
            }

            do {
                guard let data else {
                    return
                }
                try await webSocketTask.send(.data(data))
                Logger.webSocket.trace("SEND: \(syncMsg.debugDescription)")
            } catch {
                Logger.webSocket
                    .warning("Error in sending websocket data: \(error.localizedDescription, privacy: .public)")
                await self.disconnect()
            }
        }
    }

    // ideas for additional async API for this?
//    public func sendGossip() async {
//
//    }
//
//    public func sendSubscribe() async {
//
//    }

    // MARK: WebSocket Message handlers

    /// Infinitely loops over incoming messages from the websocket and updates the state machine based on the messages
    /// received.
    private func ongoingHandleWebSocketMessage() async throws {
        while true {
            guard let webSocketTask = self.webSocketTask else {
                Logger.webSocket.warning("Receive Handler: webSocketTask is nil, terminating handler loop")
                break
            }

            try Task.checkCancellation()

            Logger.webSocket
                .trace(
                    "Receive Handler: Task not cancelled, awaiting next message, state is \(self.protocolState.rawValue, privacy: .public)"
                )

            let webSocketMessage = try await webSocketTask.receive()
            do {
                let msg = try attemptToDecode(webSocketMessage)
                await self.handleReceivedMessage(msg: msg)
            } catch {
                await self.disconnect()
            }
        }
    }

    /// Asynchronously updates the state machine and side-effect values in `WebsocketSyncConnection`
    ///
    /// this function doesn't throw on error conditions, but in some circumstances:
    ///  - if it `connectionState` is in ``SyncProtocolState/handshake`` and receives anything other than a peer msg
    ///  - if it is invoked while `connectionState` is reporting a ``SyncProtocolState/closed`` state
    /// it disconnects and shuts down the web-socket.
    private func handleReceivedMessage(msg: SyncV1Msg) async {
        switch protocolState {
        case .setup:
            Logger.webSocket.warning("RCVD: \(msg.debugDescription, privacy: .public) while in NEW state")
        case .preparing:
            if case let .peer(peerMsg) = msg {
                await MainActor.run {
                    self.targetId = peerMsg.targetId
                    self.protocolState = .ready
                }
                // TODO: handle the gossip setup - read and process the peer metadata
            } else {
                // In the handshake phase and received anything other than a valid peer message
                Logger.webSocket
                    .warning(
                        "FAILED TO PEER - RECEIVED MSG: \(msg.debugDescription, privacy: .public), shutting down WebSocket"
                    )
                await self.disconnect()
            }
        case .ready:
            switch msg {
            case let .error(errorMsg):
                Logger.webSocket.warning("RCVD ERROR: \(errorMsg.debugDescription)")

            case let .sync(syncMsg):
                guard let document = self.document,
                      let documentId = self.documentId,
                      let targetId = self.targetId,
                      let webSocketTask = self.webSocketTask
                else {
                    return
                }

                guard self.senderId == syncMsg.targetId,
                      documentId.description == syncMsg.documentId
                else {
                    Logger.webSocket
                        .warning(
                            "Sync message target and document Id don't match expected values. Received: \(syncMsg.debugDescription), targetId expected: \(self.senderId), documentId expected: \(documentId.description)"
                        )
                    return
                }

                do {
                    Logger.webSocket.trace("RCVD: Applying sync message: \(syncMsg.debugDescription)")
                    try document.receiveSyncMessage(state: self.syncState, message: syncMsg.data)
                    // TODO: enable gossip of sending changed heads (if in gossip mode)
                    if let syncData = document.generateSyncMessage(state: self.syncState) {
                        // if we have a sync message, then sync isn't complete...
                        // verify the state is set correctly, update it if not
                        if self.syncInProgress != true {
                            await MainActor.run {
                                self.syncInProgress = true
                            }
                        }
                        let replyingSyncMsg = SyncV1Msg.SyncMsg(
                            documentId: documentId.description,
                            senderId: self.senderId,
                            targetId: targetId,
                            sync_message: syncData
                        )
                        Logger.webSocket
                            .trace(" - SYNC: Sending another sync msg after applying updates")
                        let replyData = try SyncV1Msg.encode(replyingSyncMsg)
                        try await webSocketTask.send(.data(replyData))
                        Logger.webSocket.trace("SEND: \(replyingSyncMsg.debugDescription)")
                    } else {
                        await MainActor.run {
                            self.syncInProgress = false
                        }
                        Logger.webSocket.trace(" - SYNC: No further sync msgs needed - sync complete.")
                    }
                } catch {
                    Logger.webSocket
                        .error(
                            "Error while applying sync message \(error.localizedDescription, privacy: .public), DISCONNECTING!"
                        )
                    Logger.webSocket.error("sync data raw bytes: \(syncMsg.data.hexEncodedString(), privacy: .public)")
                    await self.disconnect()
                }
            case let .ephemeral(msg):
                Logger.webSocket.trace("RCVD: Ephemeral message: \(msg.debugDescription, privacy: .public).")
            // TODO: enable a callback or something to allow someone external to handle the ephemeral messages
            case let .remoteHeadsChanged(msg):
                Logger.webSocket
                    .trace("RCVD: remote head's changed message: \(msg.debugDescription, privacy: .public).")
                // TODO: enable gossiping responses

            case let .unavailable(inside_msg):
                Logger.webSocket.trace("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")

            // Messages that are technically allowed, but not common in the "ready" state unless
            // you're "serving up multiple documents" (this implementation links to a single Automerge
            // document.

            case let .request(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            case let .remoteSubscriptionChange(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            case let .leave(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            // Messages that are always unexpected while in the "ready" state

            case let .peer(inside_msg):
                Logger.webSocket.error("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .join(inside_msg):
                Logger.webSocket.error("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unknown(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            }

        case .closed:
            Logger.webSocket.warning("RCVD: \(msg.debugDescription, privacy: .public), disconnecting (again?)")
            // cleanup - we shouldn't ever be here, but just in case...
            await self.disconnect()
        }
    }
}
