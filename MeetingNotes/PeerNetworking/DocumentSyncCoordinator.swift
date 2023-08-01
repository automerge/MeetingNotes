import Automerge
import Combine
import Foundation
import Network
import OSLog
#if os(iOS)
import UIKit // for UIDevice.name access
#endif

/// A type that provides type-safe strings for TXTRecord publications with Bonjour
enum TXTRecordKeys {
    /// The document identifier.
    static var doc_id = "doc_id"
    /// The peer identifier.
    static var peer_id = "peer_id"
    /// The human-readable name for the peer.
    static var name = "name"
}

/// A collection of User Default keys for the app.
enum MeetingNotesDefaultKeys {
    /// The key to the string that the app broadcasts to represent you when sharing and syncing MeetingNotes.
    static let sharingIdentity = "sharingIdentity"
}

final class DocumentSyncCoordinator: ObservableObject {
    // support multiple documents
    var documents: [UUID: MeetingNotesDocument] = [:]
    var txtRecords: [UUID: NWTXTRecord] = [:]
    var listeners: [UUID: NWListener] = [:]
    @Published var listenerState: [UUID: NWListener.State] = [:]

    /// Looks up and returns a reference for a document for an initiated Peer Connection
    ///
    /// Primarily in order to attempt to send and receive sync updates.
    func automergeDocument(for docId: UUID) -> Document? {
        documents[docId]?.doc
    }

    func registerDocument(_ document: MeetingNotesDocument) {
        documents[document.id] = document

        var txtRecord = NWTXTRecord()
        txtRecord[TXTRecordKeys.name] = name
        txtRecord[TXTRecordKeys.peer_id] = peerId.uuidString
        txtRecord[TXTRecordKeys.doc_id] = document.id.uuidString
        txtRecords[document.id] = txtRecord
    }

    @Published var name: String {
        didSet {
            // update a listener, if running, with the new name.
            resetName(name)
        }
    }

    var browser: NWBrowser?
    @Published var browserResults: [NWBrowser.Result] = []
    @Published var browserState: NWBrowser.State = .setup
    var autoconnect: Bool = false

    @Published var connections: [SyncConnection] = []

    func removeConnection(_ connectionId: UUID) {
        connections.removeAll { $0.connectionId == connectionId }
    }

    @Published var listenerSetupError: Error? = nil
    @Published var listenerStatusError: NWError? = nil

    let peerId = UUID()
    let syncQueue = DispatchQueue(label: "PeerSyncQueue")
    var timerCancellable: Cancellable?
    var syncTrigger: PassthroughSubject<Void, Never> = PassthroughSubject()

    static func defaultSharingIdentity() -> String {
        #if os(iOS)
        UIDevice().name
        #elseif os(macOS)
        Host.current().localizedName ?? "MeetingNotes User"
        #endif
    }

    init() {
        self.name = UserDefaults.standard
            .string(forKey: MeetingNotesDefaultKeys.sharingIdentity) ?? DocumentSyncCoordinator.defaultSharingIdentity()
        Logger.syncController.debug("SYNC CONTROLLER INIT, peer \(self.peerId.uuidString, privacy: .public)")
    }

    func activate() {
        Logger.syncController.debug("SYNC PEER  \(self.peerId.uuidString, privacy: .public): ACTIVATE")
        browserState = .setup
        startBrowsing()
        for documentId in documents.keys {
            listenerState[documentId] = .setup
            setupBonjourListener(for: documentId)
        }
        timerCancellable = Timer.publish(every: .milliseconds(100), on: .main, in: .default)
            .autoconnect()
            .receive(on: syncQueue)
            .sink(receiveValue: { [weak self] _ in
                self?.syncTrigger.send()
            })
    }

    func deactivate() {
        Logger.syncController.debug("SYNC PEER  \(self.peerId.uuidString, privacy: .public): CANCEL")
        timerCancellable?.cancel()
        stopBrowsing()
        stopListening()
        cancelAllConnections()
        timerCancellable = nil
    }

    // MARK: NWBrowser

    func attemptToConnectToPeer(_ endpoint: NWEndpoint, forPeer peerId: String, withDoc documentId: UUID) {
        Logger.syncController
            .debug(
                "Attempting to establish connection to \(peerId, privacy: .public) through \(endpoint.debugDescription, privacy: .public) "
            )
        if connections.filter({ conn in
            conn.peerId == peerId
        }).isEmpty {
            Logger.syncController
                .debug("No connection stored for \(peerId, privacy: .public)")
            let newConnection = SyncConnection(
                endpoint: endpoint,
                peerId: peerId,
                trigger: syncTrigger.eraseToAnyPublisher(),
                documentId: documentId
            )
            DispatchQueue.main.async {
                self.connections.append(newConnection)
            }
        }
    }

    func delayAndAttemptToConnect(_ endpoint: NWEndpoint, forPeer peerId: String, withDoc documentId: UUID) {
        Task {
            let delay = Int.random(in: 250 ... 1000)
            Logger.syncController
                .info(
                    "Delaying \(delay, privacy: .public) ms before attempting connect to \(peerId, privacy: .public) at \(endpoint.debugDescription, privacy: .public)"
                )
            try await Task.sleep(until: .now + .milliseconds(delay), clock: .continuous)
            self.attemptToConnectToPeer(endpoint, forPeer: peerId, withDoc: documentId)
        }
    }

    // Start browsing for services.
    fileprivate func startBrowsing() {
        // Create parameters, and allow browsing over a peer-to-peer link.
        let browserNetworkParameters = NWParameters()
        browserNetworkParameters.includePeerToPeer = true

        // Browse for the Automerge sync bonjour service type.
        let newNetworkBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: AutomergeSyncProtocol.bonjourType, domain: nil),
            using: browserNetworkParameters
        )

        newNetworkBrowser.stateUpdateHandler = { newState in
            switch newState {
            case let .failed(error):
                self.browserState = .failed(error)
                // Restart the browser if it loses its connection.
                if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                    Logger.syncController.info("Browser failed with \(error, privacy: .public), restarting")
                    newNetworkBrowser.cancel()
                    self.startBrowsing()
                } else {
                    Logger.syncController.warning("Browser failed with \(error, privacy: .public), stopping")
                    newNetworkBrowser.cancel()
                }
            case .ready:
                self.browserState = .ready
            case .cancelled:
                self.browserState = .cancelled
                self.browserResults = []
            default:
                break
            }
        }

        newNetworkBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Logger.syncController.debug("browser update shows \(results.count, privacy: .public) result(s):")
            for res in results {
                Logger.syncController
                    .debug(
                        "  \(res.endpoint.debugDescription, privacy: .public) \(res.metadata.debugDescription, privacy: .public)"
                    )
            }
            guard let self else {
                return
            }
            // Only show broadcasting peers that doesn't have the name provided by this app.
            let filtered = results.filter { result in
                if case let .bonjour(txtrecord) = result.metadata,
                   txtrecord[TXTRecordKeys.peer_id] != self.peerId.uuidString
                {
                    return true
                }
                return false
            }
            .sorted(by: {
                $0.hashValue < $1.hashValue
            })

            self.browserResults = filtered

//            if self.autoconnect {
//                // check list of current connections, if not in it - enqueue for connecting
//                for potentialPeer in filtered {
//                    Logger.syncController
//                        .debug("Checking potential peer \(potentialPeer.endpoint.debugDescription, privacy: .public)")
//                    if case let .bonjour(txtrecord) = potentialPeer.metadata {
//                        if let peerId = txtrecord[TXTRecordKeys.peer_id] {
//                            if self.connections.filter({ $0.peerId == peerId }).isEmpty {
//                                self.delayAndAttemptToConnect(potentialPeer.endpoint, forPeer: peerId)
//                            }
//                        }
//                    }
//                }
//            }
        }

        Logger.syncController.info("Activating NWBrowser \(newNetworkBrowser.debugDescription, privacy: .public)")
        self.browser = newNetworkBrowser
        // Start browsing and ask for updates on the main queue.
        newNetworkBrowser.start(queue: .main)
    }

    fileprivate func stopBrowsing() {
        guard let browser else { return }
        Logger.syncController.info("Terminating NWBrowser")
        browser.cancel()
        self.browser = nil
    }

    fileprivate func cancelAllConnections() {
        for conn in connections {
            conn.cancel()
        }
    }

    // MARK: NWListener handlers

    // Start listening and advertising.
    fileprivate func setupBonjourListener(for documentId: UUID) {
        guard let txtRecordForDoc = txtRecords[documentId] else {
            Logger.syncController
                .warning(
                    "Attempting to establish listener for unregistered document: \(documentId.uuidString, privacy: .public)"
                )
            return
        }
        do {
            // Create the listener object.
            let listener = try NWListener(using: NWParameters.peerSyncParameters(documentId: documentId.uuidString))
            // Set the service to advertise.
            listener.service = NWListener.Service(
                type: AutomergeSyncProtocol.bonjourType,
                txtRecord: txtRecordForDoc
            )
            listener.stateUpdateHandler = { [weak self] newState in
                self?.listenerState[documentId] = newState
                switch newState {
                case .ready:
                    if let port = listener.port {
                        Logger.syncController
                            .info("Bonjour listener ready on \(port.rawValue, privacy: .public)")
                    } else {
                        Logger.syncController
                            .info("Bonjour listener ready (no port listed)")
                    }
                    self?.listenerStatusError = nil
                case let .failed(error):
                    if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                        Logger.syncController
                            .warning("Bonjour listener failed with \(error, privacy: .public), restarting.")
                        listener.cancel()
                        self?.listeners.removeValue(forKey: documentId)
                        self?.setupBonjourListener(for: documentId)
                    } else {
                        Logger.syncController
                            .error("Bonjour listener failed with \(error, privacy: .public), stopping.")
                        self?.listenerStatusError = error
                        listener.cancel()
                    }
                default:
                    self?.listenerStatusError = nil
                }
            }

            // The system calls this when a new connection arrives at the listener.
            // Start the connection to accept it, or cancel to reject it.
            listener.newConnectionHandler = { [weak self] newConnection in
                Logger.syncController
                    .debug(
                        "Receiving connection request from \(newConnection.endpoint.debugDescription, privacy: .public)"
                    )
                Logger.syncController
                    .debug(
                        "  Connection details: \(newConnection.debugDescription, privacy: .public)"
                    )
                guard let self else { return }

                if connections.filter({ conn in
                    conn.endpoint == newConnection.endpoint
                }).isEmpty {
                    Logger.syncController
                        .info(
                            "Endpoint not yet recorded, accepting connection from \(newConnection.endpoint.debugDescription, privacy: .public)"
                        )
                    let peerConnection = SyncConnection(
                        connection: newConnection,
                        trigger: syncTrigger.eraseToAnyPublisher(),
                        documentId: documentId
                    )
                    connections.append(peerConnection)
                } else {
                    Logger.syncController
                        .info(
                            "Inbound connection already exists for \(newConnection.endpoint.debugDescription, privacy: .public), cancelling the connection request."
                        )
                    // If we already have a connection to that endpoint, don't add another
                    newConnection.cancel()
                }
            }

            // Start listening, and request updates on the main queue.
            listener.start(queue: .main)
            listeners[documentId] = listener
            Logger.syncController
                .debug(
                    "Starting bonjour network listener for document id \(documentId.uuidString, privacy: .public)"
                )

        } catch {
            Logger.syncController
                .critical(
                    "Failed to create bonjour listener for document id \(documentId.uuidString, privacy: .public): \(error, privacy: .public)"
                )
            listenerSetupError = error
        }
    }

    // Stop all listeners.
    fileprivate func stopListening() {
        for (documentId, listener) in listeners {
            Logger.syncController.debug("Terminating NWListener for \(documentId.uuidString, privacy: .public)")
            listener.cancel()
            listeners.removeValue(forKey: documentId)
        }
        listeners = [:]
    }

    // Update the advertised name on the network.
    fileprivate func resetName(_ name: String) {
        for documentId in documents.keys {
            if var txtRecord = txtRecords[documentId] {
                txtRecord[TXTRecordKeys.name] = name
                txtRecords[documentId] = txtRecord

                // Reset the service to advertise.
                listeners[documentId]?.service = NWListener.Service(
                    type: AutomergeSyncProtocol.bonjourType,
                    txtRecord: txtRecord
                )
                Logger.syncController
                    .debug(
                        "Updated bonjour network listener to name \(name, privacy: .public) for document id \(documentId.uuidString, privacy: .public)"
                    )
            } else {
                Logger.syncController
                    .error(
                        "Unable to find TXTRecord for the registered Document: \(documentId.uuidString, privacy: .public)"
                    )
            }
        }
    }
}
