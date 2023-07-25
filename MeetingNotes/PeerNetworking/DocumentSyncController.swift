import Automerge
import Combine
import Foundation
import Network
import OSLog

final class DocumentSyncController: ObservableObject {
    weak var document: MeetingNotesDocument?
    var name: String {
        didSet {
            // update a listener, if running, with the new name.
            resetName(name)
        }
    }

    /// A reference to the Automerge document for an initiated Peer Connection to attempt to send sync messages.
    ///
    /// Needed for conformance to ``SyncConnectionDelegate``.
    var automergeDocument: Document? {
        document?.doc
    }

    var browser: NWBrowser?
    @Published var browserResults: [NWBrowser.Result] = []
    @Published var browserState: NWBrowser.State = .setup

    var listener: NWListener?
    @Published var listenerState: NWListener.State = .setup
    @Published var listenerSetupError: Error? = nil
    @Published var listenerStatusError: NWError? = nil
    var txtRecord: NWTXTRecord

    var connections: [NWEndpoint: SyncConnection] = [:] {
        willSet(newDictionary) {
            #if DEBUG
            Logger.syncController.debug("Updating connections to \(newDictionary.count, privacy: .public) values")
            let newkeys = Array(newDictionary.keys)
            let oldkeys = Array(connections.keys)
            let diff = newkeys.difference(from: oldkeys)
            for change in diff {
                if case let .insert(_, ep, _) = change {
                    Logger.syncController.debug(" - inserting \(ep.debugDescription, privacy: .public)")
                }
                if case let .remove(_, ep, _) = change {
                    Logger.syncController.debug(" - removing \(ep.debugDescription, privacy: .public)")
                }
            }
            #endif
        }
    }

    let syncQueue = DispatchQueue(label: "PeerSyncQueue")
    var timerCancellable: Cancellable?
    var syncTrigger: PassthroughSubject<Void, Never> = PassthroughSubject()

    init(_ document: MeetingNotesDocument, name: String) {
        self.document = document
        txtRecord = NWTXTRecord(["id": document.id.uuidString])
        txtRecord["name"] = name
        self.name = name
        self.activate()
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
        for (ep,conn) in connections {
            conn.cancel()
            Logger.syncController.debug("Cancelling stored connection to endpoint \(ep.debugDescription, privacy: .public)")
        }
        connections = [:]
        timerCancellable = nil
    }

    // MARK: NWBrowser

    func attemptToPeerConnect(_ endpoint: NWEndpoint) {
        Logger.syncController
            .debug("Attempting to establish connection to \(endpoint.debugDescription, privacy: .public)")
        if connections[endpoint] == nil, let docId = document?.id.uuidString {
            Logger.syncController
                .debug("No connection stored for \(endpoint.debugDescription, privacy: .public)")
            let newConnection = SyncConnection(
                endpoint: endpoint,
                trigger: syncTrigger.eraseToAnyPublisher(),
                delegate: self,
                docId: docId
            )
            connections[endpoint] = newConnection
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
            Logger.syncController.debug("Browser State Update: \(String(describing: newState), privacy: .public)")
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
                // Post initial results.
                self.browserState = .ready
            case .cancelled:
                self.browserState = .cancelled
                self.browserResults = []
            default:
                break
            }
        }

        // When the list of discovered endpoints changes, refresh the delegate.
        newNetworkBrowser.browseResultsChangedHandler = { results, _ in
            Logger.syncController.debug("browser update shows \(results.count, privacy: .public) result(s):")
            for res in results {
                Logger.syncController
                    .debug(
                        "  \(res.endpoint.debugDescription, privacy: .public) \(res.metadata.debugDescription, privacy: .public)"
                    )
            }
            // Only show broadcasting peers with the same document Id
            // - and that doesn't have the name provided by this app.
            let filtered = results.filter { result in
                if case let .bonjour(txtrecord) = result.metadata,
                   let uuidString = self.document?.id.uuidString,
                   txtrecord["id"] == uuidString,
                   txtrecord["name"] != self.name
                {
                    return true
                }
                return false
            }
            .sorted(by: {
                $0.hashValue < $1.hashValue
            })

            // check list of current connections, if not in it - enqueue for connecting
            for potentialPeer in filtered {
                Logger.syncController
                    .debug("Checking potential peer \(potentialPeer.endpoint.debugDescription, privacy: .public)")
                if self.connections[potentialPeer.endpoint] == nil {
                    Logger.syncController
                        .debug(
                            "\(potentialPeer.endpoint.debugDescription, privacy: .public) doesn't have a connection, enqueuing a task to connection."
                        )
                    Task {
                        let delay = Int.random(in: 50 ... 250)
                        Logger.syncController
                            .debug(
                                "Delaying \(delay, privacy: .public) ms before attempting connect to \(potentialPeer.endpoint.debugDescription, privacy: .public)"
                            )
                        try await Task.sleep(until: .now + .milliseconds(delay), clock: .continuous)
                        self.attemptToPeerConnect(potentialPeer.endpoint)
                    }
                }
            }

            self.browserResults = filtered
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
            if self.connections[newConnection.endpoint] == nil {
                Logger.syncController
                    .info(
                        "Endpoint not yet recorded, accepting connection from \(newConnection.endpoint.debugDescription, privacy: .public)"
                    )
                let peerConnection = SyncConnection(
                    connection: newConnection,
                    trigger: syncTrigger.eraseToAnyPublisher(),
                    delegate: self
                )
                self.connections[newConnection.endpoint] = peerConnection
            } else {
                Logger.syncController
                    .info(
                        "Connection already recorded for \(newConnection.endpoint.debugDescription, privacy: .public), cancelling the connection request."
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
        txtRecord["name"] = name
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

extension DocumentSyncController: SyncConnectionDelegate {
    // MARK: SyncConnectionDelegate functions

    func connectionStateUpdate(_ state: NWConnection.State, from endpoint: NWEndpoint) {
        // ?? plug this into visual feedback related to the connection...
        switch state {
        case .setup:
            Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection setup.")
        case let .waiting(nWError):
            Logger.syncController
                .debug(
                    "\(endpoint.debugDescription, privacy: .public) connection waiting: \(nWError.debugDescription, privacy: .public)."
                )
        case .preparing:
            Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection preparing.")
        case .ready:
            Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection ready.")
        case let .failed(nWError):
            Logger.syncController
                .debug(
                    "\(endpoint.debugDescription, privacy: .public) connection failed: \(nWError.debugDescription, privacy: .public)."
                )
            self.connections.removeValue(forKey: endpoint)
            
        case .cancelled:
            Logger.syncController.debug("\(endpoint.debugDescription, privacy: .public) connection cancelled.")
            self.connections.removeValue(forKey: endpoint)
        @unknown default:
            fatalError()
        }
    }

    func receivedMessage(content data: Data?, message: NWProtocolFramer.Message, from endpoint: NWEndpoint) {
        Logger.syncController.info("received protocol message")
        switch message.syncMessageType {
        case .invalid:
            Logger.syncController
                .warning("Invalid message received from \(endpoint.debugDescription, privacy: .public)")
        case .sync:
            guard let data else {
                Logger.syncController
                    .warning("Sync message received without data from \(endpoint.debugDescription, privacy: .public)")
                return
            }
            do {
                Logger.syncController.info("received sync message")
                if let connection = connections[endpoint] {
                    // When we receive a complete sync message from the underlying transport,
                    // update our automerge document, and the associated SyncState.
                    let patches = try document?.doc.receiveSyncMessageWithPatches(
                        state: connection.syncState,
                        message: data
                    )
                    if let patches {
                        Logger.syncController
                            .info(
                                "Received \(patches.count, privacy: .public) patches in \(data.count, privacy: .public) bytes"
                            )
                    } else {
                        Logger.syncController
                            .info("Received sync state update in \(data.count, privacy: .public) bytes")
                    }
                    self.refreshModel()

                    // Once the Automerge doc is updated, check (using the SyncState) to see if
                    // we believe we need to send additional messages to the peer to keep it in sync.
                    if let response = document?.doc.generateSyncMessage(state: connection.syncState) {
                        connection.sendSyncMsg(response)
                    } else {
                        // When generateSyncMessage returns nil, the remote endpoint represented by
                        // SyncState should be up to date.
                        Logger.syncController.debug("Sync complete for \(endpoint.debugDescription, privacy: .public)")
                    }
                }
            } catch {
                Logger.syncController.error("Error applying sync message: \(error, privacy: .public)")
            }
        case .id:
            Logger.syncController.info("received request for document ID")
            if let connection = connections[endpoint], let id = self.document?.id.uuidString {
                connection.sendDocumentId(id)
            }
        }
    }

    func refreshModel() {
        do {
            try self.document?.getModelUpdates()
        } catch {
            Logger.document.error("Failure in regenerating model from Automerge document: \(error, privacy: .public)")
        }
    }
}
