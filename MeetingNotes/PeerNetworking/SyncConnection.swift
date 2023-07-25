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

protocol SyncConnectionDelegate: AnyObject {
    var automergeDocument: Document? { get }
    func refreshModel()
    func connectionStateUpdate(_ state: NWConnection.State, from: NWEndpoint)
    func receivedMessage(content: Data?, message: NWProtocolFramer.Message, from: NWEndpoint)
}

final class SyncConnection {
    weak var delegate: SyncConnectionDelegate?
    var connection: NWConnection?
    /// A Boolean value that indicates this app initiated this connection.
    let initiatedConnection: Bool

    // Setting the syncstate within a Connection wrapper binds its lifetime to the
    // connection, and keeps management of sync state a bit easier than tracking it
    // separately in the DocumentSyncController.

    /// The synchronisation state associated with this connection.
    var syncState: SyncState
    var syncTriggerCancellable: Cancellable?

    /// Initiate a connection to a network endpoint to synchronise an Automerge Document.
    /// - Parameters:
    ///   - endpoint: The endpoint to attempt to connect.
    ///   - delegate: A delegate that can process Automerge sync protocol messages.
    ///   - trigger: A publisher that provides a recurring signal to trigger a sync request.
    ///   - docId: The document Id to use as a pre-shared key in TLS establishment of the connection.
    init(endpoint: NWEndpoint, trigger: AnyPublisher<Void, Never>, delegate: SyncConnectionDelegate, docId: String) {
        self.delegate = delegate
        initiatedConnection = true

        Logger.syncController.debug("Initiating connection to \(endpoint.debugDescription, privacy: .public)")
        syncState = SyncState()
        let connection = NWConnection(to: endpoint, using: NWParameters.peerSyncParameters(documentId: docId))
        self.connection = connection

        startConnection()
        syncTriggerCancellable = trigger.sink(receiveValue: { _ in
            if let syncData = delegate.automergeDocument?.generateSyncMessage(state: self.syncState) {
                Logger.syncController
                    .debug(
                        "Syncing \(syncData.count, privacy: .public) bytes to \(endpoint.debugDescription, privacy: .public)"
                    )
                self.sendSyncMsg(syncData)
            }
        })
    }

    /// Accepts and runs a connection from another network endpoint to synchronise an Automerge Document.
    /// - Parameters:
    ///   - connection: The connection provided by a listener to accept.
    ///   - delegate: A delegate that can process Automerge sync protocol messages.
    init(connection: NWConnection, trigger: AnyPublisher<Void, Never>, delegate: SyncConnectionDelegate) {
        self.delegate = delegate
        self.connection = connection
        initiatedConnection = false
        syncState = SyncState()
        Logger.syncController
            .info("Receiving connection from \(connection.endpoint.debugDescription, privacy: .public)")
        startConnection()
        syncTriggerCancellable = trigger.sink(receiveValue: { _ in
            if let syncData = delegate.automergeDocument?.generateSyncMessage(state: self.syncState) {
                Logger.syncController
                    .info(
                        "Syncing \(syncData.count, privacy: .public) bytes to \(connection.endpoint.debugDescription, privacy: .public)"
                    )
                self.sendSyncMsg(syncData)
            }
        })
    }

    /// Cancels the current connection.
    func cancel() {
        if let connection = connection {
            connection.cancel()
            Logger.syncController
                .debug("Cancelling connection to \(connection.endpoint.debugDescription, privacy: .public)")
            syncTriggerCancellable?.cancel()
            self.connection = nil
        }
    }

    // Handle starting the peer-to-peer connection for both inbound and outbound connections.
    private func startConnection() {
        guard let connection = connection else {
            return
        }

        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                Logger.syncController.info("\(String(describing: connection), privacy: .public) established")

                // When the connection is ready, start receiving messages.
                self?.receiveNextMessage()

                // Notify the delegate that the connection is ready.
                if let delegate = self?.delegate {
                    delegate.connectionStateUpdate(newState, from: connection.endpoint)
                }
            case let .failed(error):
                Logger.syncController
                    .warning(
                        "\(String(describing: connection), privacy: .public) failed with \(error, privacy: .public)"
                    )
                // Cancel the connection upon a failure.
                connection.cancel()

                if let delegate = self?.delegate {
                    // Notify the delegate when the connection fails.
                    delegate.connectionStateUpdate(newState, from: connection.endpoint)
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
        guard let connection = connection else {
            return
        }

        connection.receiveMessage { content, context, _, error in
            // Extract your message type from the received context.
            if let syncMessage = context?
                .protocolMetadata(definition: AutomergeSyncProtocol.definition) as? NWProtocolFramer.Message,
                let endpoint = self.connection?.endpoint
            {
                self.delegate?.receivedMessage(content: content, message: syncMessage, from: endpoint)
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
}
