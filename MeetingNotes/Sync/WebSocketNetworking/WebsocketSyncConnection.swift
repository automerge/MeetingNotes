import Automerge
import Combine
import Foundation
import OSLog
import PotentCBOR

/// A class that provides a WebSocket connection to sync an Automerge document.
public final class WebsocketSyncConnection: ObservableObject {
    /// The state of the WebSocket sync connection.
    public enum SyncProtocolState {
        /// A sync connection hasn't yet been requested
        case new

        /// The state is initiating and waiting to successfully peer with the recipient.
        case handshake

        /// The connection has successfully peered.
        case peered_waiting

        /// The connection is actively engaged in syncing.
        case peered_syncing

        /// The connection has terminated.
        case closed
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private let senderId: String
    private var targetId: String? = nil
    private var syncState: Automerge.SyncState
    private weak var document: Automerge.Document?
    private var documentId: DocumentId?

    // TODO: Add a delegate link of some form for a 'ephemeral' msg data handler
    // TODO: Add an indicator of if we should involve ourselves in "gossip" about updates
    // TODO: Add something that watches Documents for updates to invoke either gossip or sync depending
    // ^^ perhaps should be done outside of WebsocketSyncConnection, an over-layer that manages a strategy

    // Strategy ideas that use the lower level protocol:
    // 1 - request a document do an initial sync if available, and then be done.
    // 2 - sync once and done - sync on command only
    // 3 - sync once on command, and gossip about heads changed (i.e. let the remote side determine if they want to sync
    // or not)
    // 4 - sync once on command, and thereafter as changes come in to document - either from websocket or app updates to
    // the Document

    @Published public var connectionState: SyncProtocolState

    init(_ document: Automerge.Document? = nil, id _: DocumentId? = nil) {
        connectionState = .new
        syncState = SyncState()
        senderId = UUID().uuidString
        if let document {
            self.document = document
            if let documentId {
                self.documentId = documentId
            } else {
                self.documentId = DocumentId()
            }
        }
    }

    /// Register a document and its identifier with the WebSocket for syncing.
    /// - Parameters:
    ///   - document: The Automerge document to sync
    ///   - id: The document identifier.
    public func registerDocument(_ document: Automerge.Document, id: DocumentId) {
        self.document = document
        self.documentId = id
    }

//    public func requestDocument(_ id: DocumentId, from destination: String) async -> Automerge.Document? {
//        let tempDocument = Document()
//        self.document = tempDocument
//        self.connect(destination)
//        // wait for Peer - how long?
//        // in essence, I want to drive the state machine - so maybe _inside_ this instance isn't the right place.
//        /Static method? External?
//
//        return nil
//    }

    /// Initiates a WebSocket connection to a remote peer.
    public func connect(_ destination: String) async {
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

        // configure and start the websocket
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        // establishes the websocket
        Logger.webSocket.trace("Activating websocket to \(url, privacy: .public)")
        configureWebsocketReceiveHandler()
        guard let webSocketTask = webSocketTask else {
            #if DEBUG
            fatalError("Attempting to configure and join a nil webSocketTask")
            #else
            return
            #endif
        }
        webSocketTask.resume()

        // since we initiated the WebSocket, it's on us to send an initial 'join'
        // protocol message to start the handshake phase of the protocol
        let joinMessage = JoinMsg(senderId: senderId)
        do {
            let data = try V1Msg.encode(joinMessage)
            try await webSocketTask.send(.data(data))
            connectionState = .handshake
            // TODO: Can we extend this all the way to expecting an callback to move out of handshake mode - potentially with a timeout
        } catch {
            Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
            connectionState = .closed
            self.webSocketTask = nil
        }
    }

    /// Asynchronously disconnect the WebSocket and shut down active sessions.
    public func disconnect() async {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        connectionState = .closed
        self.webSocketTask = nil
    }

    /// Synchronously  disconnect the WebSocket and shut down active sessions.
    private func disconnect() {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        connectionState = .closed
        self.webSocketTask = nil
    }

    /// <#Description#>
    public func syncDocument() async {
        guard connectionState == .peered_waiting else {
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
            self.document != nil && self
                .documentId != nil
        ) // should be assured by the state diagram, but just in case.

        if let syncData = document.generateSyncMessage(state: self.syncState) {
            connectionState = .peered_syncing
            let syncMsg = SyncMsg(
                documentId: documentId.description,
                senderId: self.senderId,
                targetId: targetId,
                sync_message: syncData
            )
            do {
                let data = try V1Msg.encode(syncMsg)
                try await webSocketTask.send(.data(data))
            } catch {
                Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
                await self.disconnect()
            }
        }
    }

    // ideas for additiona async API for this?
//    public func gossip() async {
//
//    }
//
//    public func subscribe() async {
//
//    }

    // DRIVE THE ALMIGHTY STATE MACHINE with received messages from the WebSocket
    private func handleReceivedMessage(_ raw_data: Data) {
        switch connectionState {
        case .new:
            Logger.webSocket.warning("RCVD: .data(\(raw_data.hexEncodedString(uppercase: false)))")
        case .handshake:
            let msg = V1Msg.decodePeer(raw_data)
            if case let .peer(peerMsg) = msg {
                self.targetId = peerMsg.targetId
                self.connectionState = .peered_waiting
                // TODO: handle the gossip setup - read and process the peer metadata
            } else {
                // In the handshake phase and received anything other than a valid peer message
                Logger.webSocket
                    .warning("FAILED TO PEER - RECEIVED MSG: \(raw_data.hexEncodedString(uppercase: false))")
                self.disconnect()
            }
        case .peered_waiting:
            let msg = V1Msg.decode(raw_data, withGossip: true, withHandshake: false)
            switch msg {
            case let .error(errorMsg):
                Logger.webSocket.warning("RCVD ERROR: \(errorMsg.debugDescription)")
                self.disconnect()

            case let .sync(syncMsg):

                guard let document = self.document,
                      let documentId = self.documentId,
                      let targetId = self.targetId
                else {
                    return
                }
                guard targetId == syncMsg.targetId,
                      documentId.description == syncMsg.documentId
                else {
                    Logger.webSocket
                        .warning(
                            "Sync message target and document Id don't match expected values. Received: \(syncMsg.debugDescription), targetId expected: \(targetId), documentId expected: \(documentId.description)"
                        )
                    return
                }

                do {
                    try document.applyEncodedChanges(encoded: syncMsg.sync_message)
                    // TODO: enable gossip of sending changed heads (if in gossip mode)
                    if let syncData = document.generateSyncMessage(state: self.syncState) {
                        connectionState = .peered_syncing
                        let syncMsg = SyncMsg(
                            documentId: documentId.description,
                            senderId: self.senderId,
                            targetId: targetId,
                            sync_message: syncData
                        )
                        let data = try V1Msg.encode(syncMsg)
                        Task {
                            try await webSocketTask?.send(.data(data))
                        }
                    } else {
                        connectionState = .peered_waiting
                    }
                } catch {
                    Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
                    self.disconnect()
                }
            case .ephemeral:
                // TODO: enable a callback or something to allow someone external to handle the ephemeral messages
                break
            case .remoteheadschanged:
                // TODO: enable gossiping responses
                break

            // Unexpected messages in the "peered but waiting" state

            case let .peer(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .join(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .request(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .remoteSubscriptionChange(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unavailable(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unknown(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            }
        case .peered_syncing:
            let msg = V1Msg.decode(raw_data, withGossip: true, withHandshake: false)
            switch msg {
            case let .error(errorMsg):
                Logger.webSocket.warning("RCVD ERROR: \(errorMsg.debugDescription)")
                self.disconnect()

            case let .sync(syncMsg):
                guard let document = self.document,
                      let documentId = self.documentId,
                      let targetId = self.targetId
                else {
                    return
                }
                guard targetId == syncMsg.targetId,
                      documentId.description == syncMsg.documentId
                else {
                    Logger.webSocket
                        .warning(
                            "Sync message target and document Id don't match expected values. Received: \(syncMsg.debugDescription), targetId expected: \(targetId), documentId expected: \(documentId.description)"
                        )
                    return
                }
                do {
                    try document.applyEncodedChanges(encoded: syncMsg.sync_message)
                    // TODO: enable gossip of sending changed heads (if in gossip mode)
                    if let syncData = document.generateSyncMessage(state: self.syncState) {
                        connectionState = .peered_syncing
                        let syncMsg = SyncMsg(
                            documentId: documentId.description,
                            senderId: self.senderId,
                            targetId: targetId,
                            sync_message: syncData
                        )
                        let data = try V1Msg.encode(syncMsg)
                        Task {
                            try await webSocketTask?.send(.data(data))
                        }
                    } else {
                        connectionState = .peered_waiting
                    }
                } catch {
                    Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
                    self.disconnect()
                }
            case .ephemeral:
                // TODO: enable a callback or something to allow someone external to handle the ephemeral messages
                break
            case .remoteheadschanged:
                // TODO: enable gossiping responses
                break

            // Unexpected messages in the "peered but waiting" state

            case let .peer(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .join(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .request(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .remoteSubscriptionChange(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unavailable(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            case let .unknown(inside_msg):
                Logger.webSocket.warning("RCVD unexpected msg: \(inside_msg.debugDescription, privacy: .public)")
            }

        case .closed:
            Logger.webSocket.warning("RCVD: .data(\(raw_data.hexEncodedString(uppercase: false)))")
            // cleanup - we shouldn't ever be here, but just in case...
            self.disconnect()
        }
    }

    private func configureWebsocketReceiveHandler() {
        webSocketTask?.receive { result in
            Logger.webSocket.trace("Received websocket message")
            switch result {
            case let .failure(error):
                Logger.webSocket.warning("RCVD: .failure(\(error.localizedDescription)")
                print(error.localizedDescription)
                // failure from the websocket
                self.webSocketTask?.cancel()
                self.webSocketTask = nil
                self.connectionState = .closed

            case let .success(message):
                switch message {
                case let .string(text):
                    Logger.webSocket.warning("RCVD: .string(\(text)")
                case let .data(data):
                    // Handle binary data
                    self.handleReceivedMessage(data)
                @unknown default:
                    break
                }
            }
        }
    }
}
