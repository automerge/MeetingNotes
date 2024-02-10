import Automerge
import Combine
import Foundation
import OSLog
import PotentCBOR

private struct TimeoutError: LocalizedError {
    var errorDescription: String? = "Task timed out before completion"
}

private struct SyncComplete: LocalizedError {
    var errorDescription: String? = "The synchronization process is complete"
}

private struct DocumentUnavailable: LocalizedError {
    var errorDescription: String? = "The requested document isn't available"
}

/// A class that provides a WebSocket connection to sync an Automerge document.
public final class WebsocketSyncConnection: ObservableObject {
    /// The state of the WebSocket sync connection.
    public enum SyncProtocolState {
        /// A sync connection hasn't yet been requested
        case new

        /// The state is initiating and waiting to successfully peer with the recipient.
        case handshake

        /// The connection has successfully peered.
        case peered

        /// The connection has terminated.
        case closed
    }

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

    // TODO: Add a delegate link of some form for a 'ephemeral' msg data handler
    // TODO: Add an indicator of if we should involve ourselves in "gossip" about updates
    // TODO: Add something that watches Documents for updates to invoke either gossip or sync depending
    // ^^ perhaps should be done outside of WebsocketSyncConnection, an over-layer that manages a strategy

    @Published public var connectionState: SyncProtocolState

    // having register after initialization lets us add within a SwiftUI view, and then
    // configure and activate things onAppear within the view...
    public init(_ document: Automerge.Document?, id _: DocumentId?) {
        connectionState = .new
        syncState = SyncState()
        senderId = UUID().uuidString
        self.document = document
        if let documentId {
            self.documentId = documentId
        } else {
            self.documentId = DocumentId()
        }
    }

    // having register after initialization lets us add within a SwiftUI view, and then
    // configure and activate things onAppear within the view...
    public func registerDocument(_ document: Automerge.Document, id: DocumentId) {
        self.document = document
        self.documentId = id
    }

    public static func syncDocument(
        _ document: Automerge.Document,
        id: DocumentId,
        to destination: String
    ) async throws -> WebsocketSyncConnection {
        let websocketconnection = WebsocketSyncConnection(document, id: id)

        try await websocketconnection.connect(destination)
        return websocketconnection
    }

    public static func requestDocument(
        _ id: DocumentId,
        from destination: String,
        ongoing: Bool = false
    ) async throws -> (Automerge.Document, WebsocketSyncConnection)? {
        let tempDocument = Document()
        let websocketconnection = WebsocketSyncConnection(tempDocument, id: id)

        try await websocketconnection.connect(destination)

        try Task.checkCancellation()

        guard websocketconnection.connectionState == .peered else { return nil }

        // enable the request...
        try await websocketconnection.requestDocument()
        websocketconnection.receiveHandler = nil

        if ongoing {
            // fire up an ongoing process to maintain synchronization
            websocketconnection.receiveHandler = Task {
                try await websocketconnection.receiveAndHandleWebSocketMessages()
            }
            await websocketconnection.initiateSync()
        }

        return (tempDocument, websocketconnection)
    }

    /// Initiates a WebSocket connection to a remote peer.
    @MainActor
    public func connect(_ destination: String) async throws {
        guard connectionState == .new || connectionState == .closed else {
            return
        }
        guard self.document != nil, self.documentId != nil else {
            Logger.webSocket.warning("Attempting to join a connection without a document registered")
            return
        }
        guard let url = URL(string: destination) else {
            Logger.webSocket.warning("Destination provided is not a valid URL")
            return
        }

        // reset the document's synchronization state maintained by the connection
        syncState = SyncState()

        // establishes the websocket
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)

        Logger.webSocket.trace("Activating websocket to \(url, privacy: .public)")
        guard let webSocketTask = webSocketTask else {
            #if DEBUG
            fatalError("Attempting to configure and join a nil webSocketTask")
            #else
            return
            #endif
        }
        // start the websocket processing things
        webSocketTask.resume()

        // since we initiated the WebSocket, it's on us to send an initial 'join'
        // protocol message to start the handshake phase of the protocol
        let joinMessage = JoinMsg(senderId: senderId)
        let data = try V1Msg.encode(joinMessage)
        try await webSocketTask.send(.data(data))
        connectionState = .handshake

        // Race a timeout against receiving a Peer message from the other side
        // of the WebSocket connection. If we fail that race, shut down the connection
        // and move into a .closed connectionState
        let websocketMsg = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                // retrieve the next websocket message
                try await webSocketTask.receive()
            }

            group.addTask {
                // allow for 3.5 second timeout to get the next message from the server
                // and process it into relevant local state on this final class.
                try await Task.sleep(for: .seconds(3.5))
                throw TimeoutError()
            }

            guard let msg = try await group.next() else {
                throw CancellationError()
            }
            // cancel all ongoing tasks (the websocket receive request, in this case)
            group.cancelAll()
            return msg
        }

        // Now that we have the WebSocket message, figure out if we got what we expected.
        // For the sync protocol handshake phase, it's essentially "peer or die" since
        // we were the initiating side of the connection.
        switch websocketMsg {
        case let .data(raw_data):
            let msg = V1Msg.decodePeer(raw_data)
            if case let .peer(peerMsg) = msg {
                Logger.webSocket.trace("Peered to targetId: \(peerMsg.senderId) \(peerMsg.debugDescription)")
                await MainActor.run {
                    self.targetId = peerMsg.senderId
                    self.connectionState = .peered
                }
                // TODO: handle the gossip setup - read and process the peer metadata
            } else {
                // In the handshake phase and received anything other than a valid peer message
                let decodeAttempted = V1Msg.decode(raw_data, withGossip: true, withHandshake: true)
                Logger.webSocket
                    .warning("FAILED TO PEER - RECEIVED MSG: \(decodeAttempted.debugDescription)")
                await self.disconnect()
            }

        case let .string(string):
            // In the handshake phase and received anything other than a valid peer message
            Logger.webSocket
                .warning("FAILED TO PEER - RECEIVED MSG: \(string)")
            await self.disconnect()
        @unknown default:
            // In the handshake phase and received anything other than a valid peer message
            Logger.webSocket
                .error("Unknown websocket message received: \(String(describing: websocketMsg))")
            await self.disconnect()
        }
    }

    /// Asynchronously disconnect the WebSocket and shut down active sessions.
    public func disconnect() async {
        await MainActor.run {
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.receiveHandler?.cancel()
            self.connectionState = .closed
            self.webSocketTask = nil
        }
    }

    public func runOngoingSync() async throws {
        // Co-operatively check to see if we're cancelled, and if so - we can bail out before
        // going into the receive loop.
        try Task.checkCancellation()

        // verify we're in the right state before invoking the recursive (async) handler setup
        // and start the process of synchronizing the document.
        if self.connectionState == .peered {
            // NOTE: this is technically a race between do we accept a message and do something
            // with it (possibly changing state), or do we initiate a sync ourselves. In practice
            // against Automerge-repo code, it doesn't proactively ask us to do anything, playing
            // a more reactive role, but it's worth being away its a possibility.
            self.receiveHandler = Task {
                try await receiveAndHandleWebSocketMessages()
            }

            // NOTE(heckj): This causes `await connect()` to jump from having
            // peered pretty directly into an initial document sync. I'm not 100% convinced
            // that's the right way to go, and that maybe there should be a layer over the
            // async methods here that "watch" the sync state and drive the choices and messages
            // and behaviors based on a 'strategy'.
            //
            // The two obvious strategies (barring enabling the 'gossip' mechanisms in the protocol)
            // each with two variants - 'one-and-done' and 'ongoing-sync'. The strategies so far:
            //
            //  1. I have a document, here, sync it and be done (a one-off sort of thing)
            //  2. I have a document, sync it and keep it up to date
            //     (ongoing sync while the websocket is connected, and possibly handling
            //      some "attempt to reconnect" and continue bits)
            //  3. I want a document, request one - and if it's available be done (another one-off)
            //  4. I want a document, request one, and there-after keep it synced as you or I make
            //     updates (again - with possible reconnect and continue if the websocket fails

            // I haven't quite sorted how gossip is used in the protocol, but additional variations
            // on strategies might include:
            //
            // A) sync once on command, and gossip about heads changed. Implying that the remote
            //    side determine if they want to sync or not, and send a sync command if so.
            // B) primarily gossip if the connection is constrained (low data?), syncing only
            //    periodically.

            // kick off an initial sync
            await initiateSync()
        }
    }

    public func requestDocument() async throws {
        // verify we're already connected and peered
        guard connectionState == .peered,
              let document = self.document,
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

        guard let syncData = document.generateSyncMessage(state: self.syncState) else { return }

        let requestMsg = RequestMsg(
            documentId: documentId.description,
            senderId: self.senderId,
            targetId: targetId,
            sync_message: syncData
        )
        var data: Data? = nil
        do {
            data = try V1Msg.encode(requestMsg)
        } catch {
            Logger.webSocket.warning("Error encoding request message: \(error.localizedDescription, privacy: .public)")
        }

        do {
            guard let data = data else {
                return
            }
            // Logger.webSocket.trace("SEND: \(syncMsg.debugDescription)")
            // Logger.webSocket.trace("RAW WEBSOCKET BYTES: \(data.hexEncodedString())")
            // Logger.webSocket.trace("SYNC MESSAGE BYTES: \(syncMsg.data.hexEncodedString())")
            try await webSocketTask.send(.data(data))
        } catch {
            Logger.webSocket
                .warning("Error in sending websocket data: \(error.localizedDescription, privacy: .public)")
            await self.disconnect()
        }

        do {
            while true {
                try Task.checkCancellation()
                Logger.webSocket.trace("Request and Sync Receive Handler: Task not cancelled, awaiting next message:")

                let webSocketMessage = try await webSocketTask.receive()
                switch webSocketMessage {
                case let .data(data):
                    try await self.handleRequestAndSyncMessages(data)
                case let .string(string):
                    Logger.webSocket.warning("RCVD: .string(\(string)")
                @unknown default:
                    Logger.webSocket.error("Unknown websocket message type: \(String(describing: webSocketMessage))")
                    await self.disconnect()
                }
            }
        } catch {}
    }

    /// Start a synchronization process for the Automerge document
    public func initiateSync() async {
        guard connectionState == .peered else {
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
                self.connectionState = .peered
            }
            let syncMsg = SyncMsg(
                documentId: documentId.description,
                senderId: self.senderId,
                targetId: targetId,
                sync_message: syncData
            )
            var data: Data? = nil
            do {
                data = try V1Msg.encode(syncMsg)
            } catch {
                Logger.webSocket.warning("Error encoding data: \(error.localizedDescription, privacy: .public)")
            }

            do {
                guard let data = data else {
                    return
                }
                // Logger.webSocket.trace("SEND: \(syncMsg.debugDescription)")
                // Logger.webSocket.trace("RAW WEBSOCKET BYTES: \(data.hexEncodedString())")
                // Logger.webSocket.trace("SYNC MESSAGE BYTES: \(syncMsg.data.hexEncodedString())")
                try await webSocketTask.send(.data(data))
            } catch {
                Logger.webSocket
                    .warning("Error in sending websocket data: \(error.localizedDescription, privacy: .public)")
                await self.disconnect()
            }
        }
    }

    // ideas for additional async API for this?
//    public func gossip() async {
//
//    }
//
//    public func subscribe() async {
//
//    }

    // async websocket message receive and process
    private func receiveAndHandleWebSocketMessages() async throws {
        while true {
            guard let webSocketTask = self.webSocketTask else {
                Logger.webSocket.warning("Receive Handler: webSocketTask is nil, terminating handler loop")
                break
            }

            try Task.checkCancellation()
            Logger.webSocket.trace("Receive Handler: Task not cancelled, awaiting next message:")

            let webSocketMessage = try await webSocketTask.receive()
            switch webSocketMessage {
            case let .data(data):
                await self.handleReceivedMessage(data)
            case let .string(string):
                Logger.webSocket.warning("RCVD: .string(\(string)")
            @unknown default:
                Logger.webSocket.error("Unknown websocket message type: \(String(describing: webSocketMessage))")
                await self.disconnect()
            }
        }
    }

    // Respond to incoming messages and drive the state machine of this connection.
    private func handleReceivedMessage(_ raw_data: Data) async {
        switch connectionState {
        case .new:
            Logger.webSocket.warning("RCVD: .data(\(raw_data.hexEncodedString(uppercase: false)))")
        case .handshake:
            let msg = V1Msg.decodePeer(raw_data)
            if case let .peer(peerMsg) = msg {
                await MainActor.run {
                    self.targetId = peerMsg.targetId
                    self.connectionState = .peered
                }
                // TODO: handle the gossip setup - read and process the peer metadata
            } else {
                // In the handshake phase and received anything other than a valid peer message
                Logger.webSocket
                    .warning("FAILED TO PEER - RECEIVED MSG: \(raw_data.hexEncodedString(uppercase: false))")
                await self.disconnect()
            }
        case .peered:
            let msg = V1Msg.decode(raw_data, withGossip: true, withHandshake: false)
            switch msg {
            case let .error(errorMsg):
                Logger.webSocket.warning("RCVD ERROR: \(errorMsg.debugDescription)")
                await self.disconnect()

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
                    try document.applyEncodedChanges(encoded: syncMsg.data)
                    // TODO: enable gossip of sending changed heads (if in gossip mode)
                    if let syncData = document.generateSyncMessage(state: self.syncState) {
                        let syncMsg = SyncMsg(
                            documentId: documentId.description,
                            senderId: self.senderId,
                            targetId: targetId,
                            sync_message: syncData
                        )
                        Logger.webSocket
                            .trace(
                                " - SYNC: Sending another sync msg after applying updates: \(syncMsg.debugDescription)"
                            )
                        let data = try V1Msg.encode(syncMsg)
                        try await webSocketTask.send(.data(data))
                    } else {
                        Logger.webSocket.trace(" - SYNC: No further sync msgs needed - sync complete.")
                    }
                } catch {
                    Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
                    await self.disconnect()
                }
            case let .ephemeral(msg):
                Logger.webSocket.trace("RCVD: Ephemeral message: \(msg.debugDescription).")
            // TODO: enable a callback or something to allow someone external to handle the ephemeral messages
            case let .remoteheadschanged(msg):
                Logger.webSocket.trace("RCVD: remote head's changed message: \(msg.debugDescription).")
                // TODO: enable gossiping responses

            case let .unavailable(inside_msg):
                Logger.webSocket.trace("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")

            // Messages that are technically allowed, but not common in the "peered" state unless
            // you're "serving up multiple documents" (this implementation links to a single Automerge
            // document.

            case let .request(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            case let .remoteSubscriptionChange(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            // Messages that are always unexpected while in the "peered" state

            case let .peer(inside_msg):
                Logger.webSocket.error("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .join(inside_msg):
                Logger.webSocket.error("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unknown(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            }

        case .closed:
            Logger.webSocket.warning("RCVD: .data(\(raw_data.hexEncodedString(uppercase: false)))")
            // cleanup - we shouldn't ever be here, but just in case...
            await self.disconnect()
        }
    }

    // Respond to incoming messages and drive the state machine of this connection.
    private func handleRequestAndSyncMessages(_ raw_data: Data) async throws {
        switch connectionState {
        case .new:
            Logger.webSocket.warning("RCVD: .data(\(raw_data.hexEncodedString(uppercase: false)))")
        case .handshake:
            let msg = V1Msg.decodePeer(raw_data)
            if case let .peer(peerMsg) = msg {
                await MainActor.run {
                    self.targetId = peerMsg.targetId
                    self.connectionState = .peered
                }
                // TODO: handle the gossip setup - read and process the peer metadata
            } else {
                // In the handshake phase and received anything other than a valid peer message
                Logger.webSocket
                    .warning("FAILED TO PEER - RECEIVED MSG: \(raw_data.hexEncodedString(uppercase: false))")
                await self.disconnect()
            }
        case .peered:
            let msg = V1Msg.decode(raw_data, withGossip: true, withHandshake: false)
            switch msg {
            case let .error(errorMsg):
                Logger.webSocket.warning("RCVD ERROR: \(errorMsg.debugDescription)")
                throw DocumentUnavailable()

            case let .unavailable(inside_msg):
                Logger.webSocket.trace("RCVD unavailable msg: \(inside_msg.debugDescription, privacy: .public)")
                throw DocumentUnavailable()

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
                    try document.applyEncodedChanges(encoded: syncMsg.data)
                    // TODO: enable gossip of sending changed heads (if in gossip mode)
                    if let syncData = document.generateSyncMessage(state: self.syncState) {
                        let syncMsg = SyncMsg(
                            documentId: documentId.description,
                            senderId: self.senderId,
                            targetId: targetId,
                            sync_message: syncData
                        )
                        Logger.webSocket
                            .trace(
                                " - SYNC: Sending another sync msg after applying updates: \(syncMsg.debugDescription)"
                            )
                        let data = try V1Msg.encode(syncMsg)
                        try await webSocketTask.send(.data(data))
                    } else {
                        throw SyncComplete()
                    }
                } catch {
                    Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
                    await self.disconnect()
                }
            case let .ephemeral(msg):
                Logger.webSocket.trace("RCVD: Ephemeral message: \(msg.debugDescription).")
            // TODO: enable a callback or something to allow someone external to handle the ephemeral messages
            case let .remoteheadschanged(msg):
                Logger.webSocket.trace("RCVD: remote head's changed message: \(msg.debugDescription).")
                // TODO: enable gossiping responses

            // Messages that are technically allowed, but not common in the "peered" state unless
            // you're "serving up multiple documents" (this implementation links to a single Automerge
            // document.

            case let .request(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            case let .remoteSubscriptionChange(inside_msg):
                Logger.webSocket.warning("RCVD unusual msg: \(inside_msg.debugDescription, privacy: .public)")

            // Messages that are always unexpected while in the "peered" state

            case let .peer(inside_msg):
                Logger.webSocket.error("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .join(inside_msg):
                Logger.webSocket.error("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unknown(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            }

        case .closed:
            Logger.webSocket.warning("RCVD: .data(\(raw_data.hexEncodedString(uppercase: false)))")
            // cleanup - we shouldn't ever be here, but just in case...
            await self.disconnect()
        }
    }
}
