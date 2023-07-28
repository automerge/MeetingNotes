/*
 Copyright © 2022 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 WWDC Video references aligned with this code:
 - https://developer.apple.com/videos/play/wwdc2019/713/
 - https://developer.apple.com/videos/play/wwdc2020/10110/
 */

import Automerge
import Combine
import Foundation
import Network
import OSLog

final class SyncConnection: ObservableObject {
    weak var syncController: DocumentSyncCoordinator?
    /// A unique identifier to track the connections for comparison against existing connections.
    var connectionId = UUID()
    var connection: NWConnection?
    /// A Boolean value that indicates this app initiated this connection.

    @Published var connectionState: NWConnection.State = .setup
    @Published var endpoint: NWEndpoint?
    /// The peer Id for the connection endpoint, only set on outbound connections.
    var peerId: String?

    /// The synchronisation state associated with this connection.
    var syncState: SyncState

    /// The cancellable subscription to the trigger mechanism that attempts sync updates.
    var syncTriggerCancellable: Cancellable?

    /// Initiate a connection to a network endpoint to synchronise an Automerge Document.
    /// - Parameters:
    ///   - endpoint: The endpoint to attempt to connect.
    ///   - delegate: A delegate that can process Automerge sync protocol messages.
    ///   - trigger: A publisher that provides a recurring signal to trigger a sync request.
    ///   - docId: The document Id to use as a pre-shared key in TLS establishment of the connection.
    init(
        endpoint: NWEndpoint,
        peerId: String,
        trigger: AnyPublisher<Void, Never>,
        controller: DocumentSyncCoordinator,
        docId: String
    ) {
        self.syncController = controller

        Logger.syncController.debug("Initiating connection to \(endpoint.debugDescription, privacy: .public)")
        syncState = SyncState()
        let connection = NWConnection(to: endpoint, using: NWParameters.peerSyncParameters(documentId: docId))
        self.connection = connection
        self.endpoint = endpoint
        self.peerId = peerId

        startConnection(trigger)
    }

    /// Accepts and runs a connection from another network endpoint to synchronise an Automerge Document.
    /// - Parameters:
    ///   - connection: The connection provided by a listener to accept.
    ///   - delegate: A delegate that can process Automerge sync protocol messages.
    init(connection: NWConnection, trigger: AnyPublisher<Void, Never>, controller: DocumentSyncCoordinator) {
        self.syncController = controller
        self.connection = connection
        self.endpoint = connection.endpoint
        syncState = SyncState()
        Logger.syncController
            .info("Receiving connection from \(connection.endpoint.debugDescription, privacy: .public)")

        startConnection(trigger)
    }

    /// Cancels the current connection.
    func cancel() {
        if let connection = connection {
            connection.cancel()
            if let peerId {
                Logger.syncController
                    .debug("Cancelling outbound connection to peer \(peerId, privacy: .public)")
            } else {
                Logger.syncController
                    .debug(
                        "Cancelling inbound connection from endpoint \(connection.endpoint.debugDescription, privacy: .public)"
                    )
            }
            syncTriggerCancellable?.cancel()
            self.connection = nil
        }
    }

    // Handle starting the peer-to-peer connection for both inbound and outbound connections.
    private func startConnection(_ trigger: AnyPublisher<Void, Never>) {
        guard let connection = connection else {
            return
        }

        syncTriggerCancellable = trigger.sink(receiveValue: { _ in
            if let automergeDoc = self.syncController?.automergeDocument,
               let syncData = automergeDoc.generateSyncMessage(state: self.syncState)
            {
                Logger.syncController
                    .info(
                        "Syncing \(syncData.count, privacy: .public) bytes to \(connection.endpoint.debugDescription, privacy: .public)"
                    )
                self.sendSyncMsg(syncData)
            }
        })

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }

            self.connectionState = newState
            switch newState {
            case .ready:
                Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection ready.")
                // When the connection is ready, start receiving messages.
                self.receiveNextMessage()

            case let .failed(error):
                Logger.syncController
                    .warning(
                        "\(String(describing: connection), privacy: .public) failed with \(error, privacy: .public)"
                    )
                // Cancel the connection upon a failure.
                connection.cancel()
                self.syncTriggerCancellable?.cancel()
                self.syncController?.removeConnection(self.connectionId)
                self.syncTriggerCancellable = nil

            case .cancelled:
                Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection cancelled.")
                self.syncTriggerCancellable?.cancel()
                self.syncController?.removeConnection(self.connectionId)
                self.syncTriggerCancellable = nil

            case let .waiting(nWError):
                // from Network headers
                // `Waiting connections have not yet been started, or do not have a viable network`
                // So if we drop into this state, it's likely the network has shifted to non-viable
                // (for example, the wifi was disabled or dropped).
                //
                // Unclear if this is something we should retry ourselves when the associated network
                // path is again viable, or if this is something that the Network framework does on our
                // behalf.
                Logger.syncController
                    .warning(
                        "\(endpoint.debugDescription, privacy: .public) connection waiting: \(nWError.debugDescription, privacy: .public)."
                    )

            case .preparing:
                Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection preparing.")

            case .setup:
                Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection setup.")

            default:
                break
            }
        }

        // Start the connection establishment.
        connection.start(queue: .main)
    }

    /// Receive a message from the sync protocol framing, deliver it to the delegate for processing, and continue
    /// receiving messages.
    private func receiveNextMessage() {
        guard let connection = connection else {
            return
        }

        connection.receiveMessage { content, context, isComplete, error in
            Logger.syncController
                .debug("Received a \(isComplete ? "complete" : "incomplete", privacy: .public) msg on connection")
            if let content {
                Logger.syncController.debug("  - received \(content.count) bytes")
            } else {
                Logger.syncController.debug("  - received no data with msg")
            }
            // Extract your message type from the received context.
            if let syncMessage = context?
                .protocolMetadata(definition: AutomergeSyncProtocol.definition) as? NWProtocolFramer.Message,
                let endpoint = self.connection?.endpoint
            {
                self.receivedMessage(content: content, message: syncMessage, from: endpoint)
            }
            if error == nil {
                // Continue to receive more messages until you receive an error.
                self.receiveNextMessage()
            } else {
                Logger.syncController.error("error on received message: \(error)")
            }
        }
    }

    // MARK: Automerge data to Automerge Sync Protocol transforms

    /// Sends an Automerge document Id.
    /// - Parameter documentId: The document Id to send.
    func sendDocumentId(_ documentId: String) {
        // corresponds to SyncMessageType.id
        guard let connection = connection else {
            return
        }

        // Create a message object to hold the command type.
        let message = NWProtocolFramer.Message(syncMessageType: .id)
        let context = NWConnection.ContentContext(
            identifier: "DocumentId",
            metadata: [message]
        )

        // Send the app content along with the message.
        connection.send(
            content: documentId.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .idempotent
        )
    }

    /// Sends an Automerge sync data packet.
    /// - Parameter syncMsg: The data to send.
    func sendSyncMsg(_ syncMsg: Data) {
        guard let connection = connection else {
            Logger.syncController.error("PeerConnection doesn't have an active connection!")
            return
        }

        // Create a message object to hold the command type.
        let message = NWProtocolFramer.Message(syncMessageType: .sync)
        let context = NWConnection.ContentContext(
            identifier: "Sync",
            metadata: [message]
        )

        // Send the app content along with the message.
        connection.send(
            content: syncMsg,
            contentContext: context,
            isComplete: true,
            completion: .idempotent
        )
    }

    func receivedMessage(content data: Data?, message: NWProtocolFramer.Message, from endpoint: NWEndpoint) {
        switch message.syncMessageType {
        case .invalid:
            Logger.syncController
                .error("Invalid message received from \(endpoint.debugDescription, privacy: .public)")
        case .sync:
            guard let data else {
                Logger.syncController
                    .error("Sync message received without data from \(endpoint.debugDescription, privacy: .public)")
                return
            }
            do {
                // When we receive a complete sync message from the underlying transport,
                // update our automerge document, and the associated SyncState.
                if let patches = try self.syncController?.automergeDocument?.receiveSyncMessageWithPatches(
                    state: syncState,
                    message: data
                ) {
                    Logger.syncController
                        .debug(
                            "Received \(patches.count, privacy: .public) patches in \(data.count, privacy: .public) bytes"
                        )
                } else {
                    Logger.syncController
                        .debug("Received sync state update in \(data.count, privacy: .public) bytes")
                }
                self.refreshModel()

                // Once the Automerge doc is updated, check (using the SyncState) to see if
                // we believe we need to send additional messages to the peer to keep it in sync.
                if let response = self.syncController?.automergeDocument?.generateSyncMessage(state: syncState) {
                    sendSyncMsg(response)
                } else {
                    // When generateSyncMessage returns nil, the remote endpoint represented by
                    // SyncState should be up to date.
                    Logger.syncController.debug("Sync complete with \(endpoint.debugDescription, privacy: .public)")
                }
            } catch {
                Logger.syncController.error("Error applying sync message: \(error, privacy: .public)")
            }
        case .id:
            Logger.syncController.info("received request for document ID")
            if let documentId = self.syncController?.document?.id.uuidString {
                sendDocumentId(documentId)
            }
        }
    }

    func refreshModel() {
        do {
            try self.syncController?.document?.getModelUpdates()
        } catch {
            Logger.document.error("Failure in regenerating model from Automerge document: \(error, privacy: .public)")
        }
    }
}

extension SyncConnection: Identifiable {}
