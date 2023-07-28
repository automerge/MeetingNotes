import Automerge
import Combine
import Foundation
import Network
import OSLog

/// A type that provides type-safe strings for TXTRecord publications with Bonjour
enum TXTRecordKeys {
    /// The document identifier.
    static var doc_id = "doc_id"
    /// The peer identifier.
    static var peer_id = "peer_id"
    /// The human-readable name for the peer.
    static var name = "name"
}

final class DocumentSyncCoordinator: ObservableObject {
    weak var document: MeetingNotesDocument? {
        didSet {
            if let document {
                self.txtRecord[TXTRecordKeys.doc_id] = document.id.uuidString
            }
        }
    }

    @Published var name: String {
        didSet {
            // update a listener, if running, with the new name.
            resetName(name)
        }
    }

    /// A reference to the Automerge document for an initiated Peer Connection to attempt to send sync messages.
    var automergeDocument: Document? {
        document?.doc
    }

    var browser: NWBrowser?
    @Published var browserResults: [NWBrowser.Result] = []
    @Published var browserState: NWBrowser.State = .setup
    var autoconnect: Bool = true

    @Published var connections: [SyncConnection] = []

    func removeConnection(_ connectionId: UUID) {
        connections.removeAll { $0.connectionId == connectionId }
    }

    var listener: NWListener?
    @Published var listenerState: NWListener.State = .setup
    @Published var listenerSetupError: Error? = nil
    @Published var listenerStatusError: NWError? = nil
    var txtRecord: NWTXTRecord

    let peerId = UUID()
    let syncQueue = DispatchQueue(label: "PeerSyncQueue")
    var timerCancellable: Cancellable?
    var syncTrigger: PassthroughSubject<Void, Never> = PassthroughSubject()

    init(name: String) {
        txtRecord = NWTXTRecord()
        txtRecord[TXTRecordKeys.name] = name
        txtRecord[TXTRecordKeys.peer_id] = self.peerId.uuidString
        self.name = name
    }

    func activate() {
        browserState = .setup
        listenerState = .setup
        startBrowsing()
        setupBonjourListener()
        timerCancellable = Timer.publish(every: .milliseconds(100), on: .main, in: .default)
            .autoconnect()
            .receive(on: syncQueue)
            .sink(receiveValue: { [weak self] _ in
                self?.syncTrigger.send()
            })
    }

    func deactivate() {
        timerCancellable?.cancel()
        stopBrowsing()
        stopListening()
        cancelAllConnections()
        timerCancellable = nil
    }

    // MARK: NWBrowser

    func attemptToConnectToPeer(_ endpoint: NWEndpoint, forPeer peerId: String) {
        Logger.syncController
            .debug(
                "Attempting to establish connection to \(peerId, privacy: .public) through \(endpoint.debugDescription, privacy: .public) "
            )
        if connections.filter({ conn in
            conn.peerId == peerId
        }).isEmpty, let docId = document?.id.uuidString {
            Logger.syncController
                .debug("No connection stored for \(peerId, privacy: .public)")
            let newConnection = SyncConnection(
                endpoint: endpoint,
                peerId: peerId,
                trigger: syncTrigger.eraseToAnyPublisher(),
                controller: self,
                docId: docId
            )
            connections.append(newConnection)
        }
    }

    func delayAndAttemptToConnect(_ endpoint: NWEndpoint, forPeer peerId: String) {
        Task {
            let delay = Int.random(in: 250 ... 1000)
            Logger.syncController
                .info(
                    "Delaying \(delay, privacy: .public) ms before attempting connect to \(peerId, privacy: .public) at \(endpoint.debugDescription, privacy: .public)"
                )
            try await Task.sleep(until: .now + .milliseconds(delay), clock: .continuous)
            self.attemptToConnectToPeer(endpoint, forPeer: peerId)
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
//            Logger.syncController.debug("browser update shows \(results.count, privacy: .public) result(s):")
//            for res in results {
//                Logger.syncController
//                    .debug(
//                        "  \(res.endpoint.debugDescription, privacy: .public) \(res.metadata.debugDescription,
//                        privacy: .public)"
//                    )
//            }
            // Only show broadcasting peers with the same document Id
            // - and that doesn't have the name provided by this app.
            let filtered = results.filter { result in
                if case let .bonjour(txtrecord) = result.metadata,
                   let uuidString = self?.document?.id.uuidString,
                   txtrecord[TXTRecordKeys.doc_id] == uuidString,
                   txtrecord[TXTRecordKeys.peer_id] != self?.peerId.uuidString
                {
                    return true
                }
                return false
            }
            .sorted(by: {
                $0.hashValue < $1.hashValue
            })

            self?.browserResults = filtered

            if let autoconnect_enabled = self?.autoconnect, autoconnect_enabled {
                // check list of current connections, if not in it - enqueue for connecting
                for potentialPeer in filtered {
                    Logger.syncController
                        .debug("Checking potential peer \(potentialPeer.endpoint.debugDescription, privacy: .public)")
                    if case let .bonjour(txtrecord) = potentialPeer.metadata {
                        if let peerId = txtrecord[TXTRecordKeys.peer_id] {
                            if let connectionsForPeerId = self?.connections.filter({ conn in
                                conn.peerId == peerId
                            }), connectionsForPeerId.isEmpty {
                                self?.delayAndAttemptToConnect(potentialPeer.endpoint, forPeer: peerId)
                            }
                        }
                    }
                }
            }
        }

        Logger.syncController.info("Activating NWBrowser \(newNetworkBrowser.debugDescription, privacy: .public)")
        self.browser = newNetworkBrowser
        // Start browsing and ask for updates on the main queue.
        newNetworkBrowser.start(queue: .main)
    }

    fileprivate func stopBrowsing() {
        guard let browser else { return }
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
    fileprivate func setupBonjourListener() {
        guard let document else { return }
        do {
            // Create the listener object.
            let listener = try NWListener(using: NWParameters.peerSyncParameters(documentId: document.id.uuidString))
            self.listener = listener

            // Set the service to advertise.
            listener.service = NWListener.Service(
                type: AutomergeSyncProtocol.bonjourType,
                txtRecord: txtRecord
            )
            Logger.syncController
                .debug(
                    "Starting bonjour network listener for document id \(document.id.uuidString, privacy: .public)"
                )
            startListening()
        } catch {
            Logger.syncController.critical("Failed to create bonjour listener: \(error, privacy: .public)")
            listenerSetupError = error
        }
    }

    func listenerStateChanged(newState: NWListener.State) {
        listenerState = newState
        switch newState {
        case .ready:
            Logger.syncController
                .info("Bonjour listener ready on \(String(describing: self.listener?.port), privacy: .public)")
            listenerStatusError = nil
        case let .failed(error):
            if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                Logger.syncController.warning("Bonjour listener failed with \(error, privacy: .public), restarting.")
                listener?.cancel()
                listener = nil
                setupBonjourListener()
            } else {
                Logger.syncController.error("Bonjour listener failed with \(error, privacy: .public), stopping.")
                listenerStatusError = error
                listener?.cancel()
            }
        default:
            listenerStatusError = nil
        }
    }

    fileprivate func startListening() {
        listener?.stateUpdateHandler = listenerStateChanged

        // The system calls this when a new connection arrives at the listener.
        // Start the connection to accept it, or cancel to reject it.
        listener?.newConnectionHandler = { [weak self] newConnection in
            Logger.syncController
                .debug(
                    "Received connection request from \(newConnection.endpoint.debugDescription, privacy: .public)"
                )
            Logger.syncController
                .debug(
                    "  Attempted connection details \(newConnection.debugDescription, privacy: .public)"
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
                    controller: self
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
        listener?.start(queue: .main)
    }

    // Stop listening.
    fileprivate func stopListening() {
        guard let listener else { return }
        listener.cancel()
        self.listener = nil
    }

    // Update the advertised name on the network.
    fileprivate func resetName(_ name: String) {
        guard let document, let listener else { return }
        txtRecord[TXTRecordKeys.name] = name
        // Reset the service to advertise.
        listener.service = NWListener.Service(
            type: AutomergeSyncProtocol.bonjourType,
            txtRecord: txtRecord
        )
        Logger.syncController
            .debug(
                "Updated bonjour network listener to name \(name, privacy: .public) for document id \(document.id.uuidString, privacy: .public)"
            )
    }
}
