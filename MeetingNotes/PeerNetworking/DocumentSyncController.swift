import Automerge
import Foundation
import Network
import OSLog

final class DocumentSyncController: ObservableObject, PeerConnectionDelegate {
    weak var document: MeetingNotesDocument?
    var name: String {
        didSet {
            // update a listener, if running, with the new name.
            resetName(name)
        }
    }

    var browser: NWBrowser?
    @Published var browserResults: [NWBrowser.Result] = []
    @Published var browserState: NWBrowser.State = .setup

    var listener: NWListener?
    @Published var listenerState: NWListener.State = .setup
    @Published var listenerSetupError: Error? = nil
    @Published var listenerStatusError: NWError? = nil
    var txtRecord: NWTXTRecord

    var connections: [NWEndpoint: PeerConnection] = [:]
    var syncStates: [NWEndpoint: SyncState] = [:]

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
    }

    func deactivate() {
        stopBrowsing()
        stopListening()
    }

    // Peer connection delegate functions
    func connectionStateUpdate(_: NWConnection.State, from _: NWEndpoint) {
        // ?? plug this into visual feedback related to the connection...
    }

    func receivedMessage(content data: Data?, message: NWProtocolFramer.Message, from endpoint: NWEndpoint) {
        switch message.syncMessageType {
        case .invalid:
            Logger.peerlistener.warning("Invalid message received from \(endpoint.debugDescription, privacy: .public)")
        case .sync:
            guard let data else {
                Logger.peerlistener
                    .warning("Sync message received without data from \(endpoint.debugDescription, privacy: .public)")
                return
            }
            do {
                if let syncState = syncStates[endpoint], let connection = connections[endpoint] {
                    try document?.doc.receiveSyncMessage(state: syncState, message: data)
                    if let response = document?.doc.generateSyncMessage(state: syncState) {
                        connection.sendSyncMsg(response)
                    } else {
                        Logger.peerlistener.trace("Sync complete for \(endpoint.debugDescription, privacy: .public)")
                    }
                }
            } catch {
                Logger.peerlistener.error("Error applying sync message: \(error, privacy: .public)")
            }
        case .id:
            Logger.peerlistener.debug("received request for document ID")
            if let connection = connections[endpoint], let id = self.document?.id.uuidString {
                connection.sendDocumentId(id)
            }
        }
    }

    // MARK: NWBrowser

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
            Logger.peerbrowser.debug("Browser State Update: \(String(describing: newState), privacy: .public)")
            switch newState {
            case let .failed(error):
                self.browserState = .failed(error)
                // Restart the browser if it loses its connection.
                if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                    Logger.peerbrowser.info("Browser failed with \(error, privacy: .public), restarting")
                    newNetworkBrowser.cancel()
                    self.startBrowsing()
                } else {
                    Logger.peerbrowser.warning("Browser failed with \(error, privacy: .public), stopping")
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
            Logger.peerbrowser.debug("\(results.count, privacy: .public) result(s):")
            for res in results {
                Logger.peerbrowser.trace("  endpoint: \(res.endpoint.debugDescription, privacy: .public)")
                Logger.peerbrowser.trace("  metadata: \(res.metadata.debugDescription, privacy: .public)")
            }
            // Only show broadcasting peers with the same document Id - that's not this app.
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
            self.browserResults = filtered
        }

        Logger.peerbrowser.debug("Activating NWBrowser \(newNetworkBrowser.debugDescription, privacy: .public)")
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
            let listener = try NWListener(using: NWParameters.peerSyncParameters())
            self.listener = listener

            // Set the service to advertise.
            listener.service = NWListener.Service(
                type: AutomergeSyncProtocol.bonjourType,
                txtRecord: txtRecord
            )
            Logger.peerlistener
                .debug(
                    "Starting bonjour network listener for document id \(document.id.uuidString, privacy: .public)"
                )
            Logger.peerlistener.debug("listener: \(listener.debugDescription, privacy: .public)")
            startListening()
        } catch {
            Logger.peerlistener.critical("Failed to create bonjour listener: \(error, privacy: .public)")
            listenerSetupError = error
        }
    }

    func listenerStateChanged(newState: NWListener.State) {
        listenerState = newState
        switch newState {
        case .ready:
            Logger.peerlistener
                .info("Bonjour listener ready on \(String(describing: self.listener?.port), privacy: .public)")
            listenerStatusError = nil
        case let .failed(error):
            if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                Logger.peerlistener.warning("Bonjour listener failed with \(error, privacy: .public), restarting.")
                listener?.cancel()
                setupBonjourListener()
            } else {
                Logger.peerlistener.error("Bonjour listener failed with \(error, privacy: .public), stopping.")
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
            Logger.peerlistener
                .trace(
                    "Attempting to link connection from \(String(describing: newConnection.endpoint), privacy: .sensitive): \(newConnection.debugDescription, privacy: .public)"
                )
            guard let self else { return }
            if self.connections[newConnection.endpoint] == nil {
                let peerConnection = PeerConnection(connection: newConnection, delegate: self)
                self.connections[newConnection.endpoint] = peerConnection
            } else {
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
        Logger.peerlistener
            .debug(
                "Updated bonjour network listener to name \(name, privacy: .sensitive) for document id \(document.id.uuidString, privacy: .public)"
            )
    }
}
