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

/// A peer to peer sync connection to receive and send sync messages.
///
/// As soon as it is established, it attempts to commence a sync operation (send and expect to receive sync messages).
/// In addition, it includes an optional `trigger` in its initializer that, when it receives any signal value, kicks off
/// another attempt to sync the relevant Automerge document.
public final class BonjourSyncConnection: ObservableObject {
    /// A unique identifier to track the connections for comparison against existing connections.
    var connectionId = UUID()
    public var shortId: String {
        //  "41ee739d-c827-4be8-9a4f-c44a492e76cf"
        String(connectionId.uuidString.lowercased().suffix(8))
    }

    /// The document to which this connection is linked
    var documentId: DocumentId

    var connection: NWConnection?
    /// A Boolean value that indicates this app initiated this connection.

    @Published public var connectionState: NWConnection.State = .setup
    @Published public var endpoint: NWEndpoint?
    /// The peer Id for the connection endpoint, only set on outbound connections.
    var peerId: String?

    /// The synchronization state associated with this connection.
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
        documentId: DocumentId
    ) {
        self.documentId = documentId
        syncState = SyncState()
        let connection = NWConnection(
            to: endpoint,
            using: NWParameters.peerSyncParameters(documentId: documentId)
        )
        self.connection = connection
        self.endpoint = endpoint
        self.peerId = peerId
        Logger.syncConnection
            .debug(
                "\(self.shortId, privacy: .public): Initiating connection to \(endpoint.debugDescription, privacy: .public)"
            )

        startConnection(trigger)
    }

    /// Accepts and runs a connection from another network endpoint to synchronise an Automerge Document.
    /// - Parameters:
    ///   - connection: The connection provided by a listener to accept.
    ///   - delegate: A delegate that can process Automerge sync protocol messages.
    init(connection: NWConnection, trigger: AnyPublisher<Void, Never>, documentId: DocumentId) {
        self.documentId = documentId
        self.connection = connection
        self.endpoint = connection.endpoint
        syncState = SyncState()
        Logger.syncConnection
            .info(
                "\(self.shortId, privacy: .public): Receiving connection from \(connection.endpoint.debugDescription, privacy: .public)"
            )

        startConnection(trigger)
    }

    /// Cancels the current connection.
    public func cancel() {
        if let connection {
            syncTriggerCancellable?.cancel()
            if let peerId {
                Logger.syncConnection
                    .debug(
                        "\(self.shortId, privacy: .public): Cancelling outbound connection to peer \(peerId, privacy: .public)"
                    )
            } else {
                Logger.syncConnection
                    .debug(
                        "\(self.shortId, privacy: .public): Cancelling inbound connection from endpoint \(connection.endpoint.debugDescription, privacy: .public)"
                    )
            }
            connection.cancel()
            self.connectionState = .cancelled
            self.connection = nil
        }
    }

    // Handle starting the peer-to-peer connection for both inbound and outbound connections.
    private func startConnection(_ trigger: AnyPublisher<Void, Never>) {
        guard let connection else {
            return
        }

        syncTriggerCancellable = trigger.sink(receiveValue: { _ in
            if let automergeDoc = SyncController.coordinator.documents[self.documentId]?.value,
               let syncData = automergeDoc.generateSyncMessage(state: self.syncState),
               self.connectionState == .ready
            {
                Logger.syncConnection
                    .info(
                        "\(self.shortId, privacy: .public): Syncing \(syncData.count, privacy: .public) bytes to \(connection.endpoint.debugDescription, privacy: .public)"
                    )
                self.sendSyncMsg(syncData)
            }
        })

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }

            self.connectionState = newState

            switch newState {
            case .ready:
                if let endpoint = self.connection?.endpoint {
                    Logger.syncConnection
                        .debug(
                            "\(self.shortId, privacy: .public): connection to \(endpoint.debugDescription, privacy: .public) ready."
                        )
                } else {
                    Logger.syncConnection.warning("\(self.shortId, privacy: .public): connection ready (no endpoint)")
                }
                // When the connection is ready, start receiving messages.
                self.receiveNextMessage()

            case let .failed(error):
                Logger.syncConnection
                    .warning(
                        "\(self.shortId, privacy: .public): FAILED \(String(describing: connection), privacy: .public) : \(error, privacy: .public)"
                    )
                // Cancel the connection upon a failure.
                connection.cancel()
                self.syncTriggerCancellable?.cancel()
                SyncController.coordinator.removeConnection(self.connectionId)
                self.syncTriggerCancellable = nil

            case .cancelled:
                Logger.syncConnection
                    .debug(
                        "\(self.shortId, privacy: .public): CANCEL \(endpoint.debugDescription, privacy: .public) connection."
                    )
                self.syncTriggerCancellable?.cancel()
                SyncController.coordinator.removeConnection(self.connectionId)
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
                if let endpoint = self.connection?.endpoint {
                    Logger.syncConnection
                        .warning(
                            "\(self.shortId, privacy: .public): connection to \(endpoint.debugDescription, privacy: .public) waiting: \(nWError.debugDescription, privacy: .public)."
                        )
                } else {
                    Logger.syncConnection.debug("\(self.shortId, privacy: .public): connection waiting (no endpoint)")
                }

            case .preparing:
                if let endpoint = self.connection?.endpoint {
                    Logger.syncConnection
                        .debug(
                            "\(self.shortId, privacy: .public): connection to \(endpoint.debugDescription, privacy: .public) preparing."
                        )
                } else {
                    Logger.syncConnection.debug("\(self.shortId, privacy: .public): connection preparing (no endpoint)")
                }

            case .setup:
                if let endpoint = self.connection?.endpoint {
                    Logger.syncConnection
                        .debug(
                            "\(self.shortId, privacy: .public): connection to \(endpoint.debugDescription, privacy: .public) in setup."
                        )
                } else {
                    Logger.syncConnection.debug("\(self.shortId, privacy: .public): connection setup (no endpoint)")
                }
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
        guard let connection else {
            return
        }

        connection.receiveMessage { content, context, isComplete, error in
            Logger.syncConnection
                .debug(
                    "\(self.shortId, privacy: .public): Received a \(isComplete ? "complete" : "incomplete", privacy: .public) msg on connection"
                )
            if let content {
                Logger.syncConnection.debug("  - received \(content.count) bytes")
            } else {
                Logger.syncConnection.debug("  - received no data with msg")
            }
            // Extract your message type from the received context.
            if let syncMessage = context?
                .protocolMetadata(definition: P2PAutomergeSyncProtocol.definition) as? NWProtocolFramer.Message,
                let endpoint = self.connection?.endpoint
            {
                self.receivedMessage(content: content, message: syncMessage, from: endpoint)
            }
            if error == nil {
                // Continue to receive more messages until you receive an error.
                self.receiveNextMessage()
            } else {
                Logger.syncConnection.error("  - error on received message: \(error)")
                self.cancel()
            }
        }
    }

    // MARK: Automerge data to Automerge Sync Protocol transforms

    /// Sends an Automerge document Id.
    /// - Parameter documentId: The document Id to send.
    func sendDocumentId(_ documentId: DocumentId) {
        // corresponds to SyncMessageType.id
        guard let connection else {
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
            content: documentId.description.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .idempotent
        )
    }

    /// Sends an Automerge sync data packet.
    /// - Parameter syncMsg: The data to send.
    func sendSyncMsg(_ syncMsg: Data) {
        guard let connection else {
            Logger.syncConnection
                .error("\(self.shortId, privacy: .public): PeerConnection doesn't have an active connection!")
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
        guard let document = SyncController.coordinator.documents[self.documentId]?.value else {
            Logger.syncConnection
                .warning(
                    "\(self.shortId, privacy: .public): received msg for unregistered document \(self.documentId, privacy: .public) from \(endpoint.debugDescription, privacy: .public)"
                )

            return
        }
        switch message.syncMessageType {
        case .unknown:
            Logger.syncConnection
                .error(
                    "\(self.shortId, privacy: .public): Invalid message received from \(endpoint.debugDescription, privacy: .public)"
                )
        case .sync:
            guard let data else {
                Logger.syncConnection
                    .error(
                        "\(self.shortId, privacy: .public): Sync message received without data from \(endpoint.debugDescription, privacy: .public)"
                    )
                return
            }
            do {
                // When we receive a complete sync message from the underlying transport,
                // update our automerge document, and the associated SyncState.
                let patches = try document.receiveSyncMessageWithPatches(
                    state: syncState,
                    message: data
                )
                Logger.syncConnection
                    .debug(
                        "\(self.shortId, privacy: .public): Received \(patches.count, privacy: .public) patches in \(data.count, privacy: .public) bytes"
                    )

                // Once the Automerge doc is updated, check (using the SyncState) to see if
                // we believe we need to send additional messages to the peer to keep it in sync.
                if let response = document.generateSyncMessage(state: syncState) {
                    sendSyncMsg(response)
                } else {
                    // When generateSyncMessage returns nil, the remote endpoint represented by
                    // SyncState should be up to date.
                    Logger.syncConnection
                        .debug(
                            "\(self.shortId, privacy: .public): Sync complete with \(endpoint.debugDescription, privacy: .public)"
                        )
                }
            } catch {
                Logger.syncConnection
                    .error("\(self.shortId, privacy: .public): Error applying sync message: \(error, privacy: .public)")
            }
        case .id:
            Logger.syncConnection.info("\(self.shortId, privacy: .public): received request for document ID")
            sendDocumentId(self.documentId)
        case .peer:
            break
        case .leave:
            break
        case .join:
            break
        case .request:
            break
        case .unavailable:
            break
        case .ephemeral:
            break
        case .syncerror:
            break
        case .remoteHeadsChanged:
            break
        case .remoteSubscriptionChange:
            break
        }
    }
}

extension BonjourSyncConnection: Identifiable {}
