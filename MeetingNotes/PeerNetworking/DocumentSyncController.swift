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
    @Published var browserStatus: NWBrowser.State

    var listener: NWListener?
    @Published var listenerState: NWListener.State
    @Published var listenerSetupError: Error? = nil
    @Published var listenerStatusError: NWError? = nil

    var connections: [NWConnection] = []

    init(_ document: MeetingNotesDocument, name: String) {
        self.document = document
        self.name = name
        browserStatus = .setup
        listenerState = .setup
        startBrowsing()
        setupBonjourListener()
    }

    // Peer connection delegate functions
    func connectionReady() {}

    func connectionFailed() {}

    func receivedMessage(content _: Data?, message _: NWProtocolFramer.Message) {}

    // MARK: NWBrowser related pieces

    // Start browsing for services.
    func startBrowsing() {
        // Create parameters, and allow browsing over a peer-to-peer link.
        let browserNetworkParameters = NWParameters()
        browserNetworkParameters.includePeerToPeer = true

        // Browse for the Automerge sync bonjour service type.
        let newNetworkBrowser = NWBrowser(
            for: .bonjour(type: AutomergeSyncProtocol.bonjourType, domain: nil),
            using: browserNetworkParameters
        )

        newNetworkBrowser.stateUpdateHandler = { newState in
            Logger.peerbrowser.debug("Browser State Update: \(String(describing: newState), privacy: .public)")
            switch newState {
            case let .failed(error):
                self.browserStatus = .failed(error)
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
                self.browserStatus = .ready
            case .cancelled:
                self.browserStatus = .cancelled
                self.browserResults = []
            default:
                break
            }
        }

        // When the list of discovered endpoints changes, refresh the delegate.
        newNetworkBrowser.browseResultsChangedHandler = { results, _ in
            Logger.peerbrowser.debug("\(results.count, privacy: .public) results provided.")
            self.browserResults = results.sorted(by: {
                $0.hashValue < $1.hashValue
            })
        }

        Logger.peerbrowser.debug("Activating NWBrowser \(newNetworkBrowser.debugDescription, privacy: .public)")
        self.browser = newNetworkBrowser
        // Start browsing and ask for updates on the main queue.
        newNetworkBrowser.start(queue: .main)
    }

    func stopBrowsing() {
        guard let browser else { return }
        browser.cancel()
        self.browser = nil
    }

    // MARK: NWListener handlers

    // Start listening and advertising.
    func setupBonjourListener() {
        guard let document else { return }
        do {
            // Create the listener object.
            let listener = try NWListener(using: NWParameters.peerSyncParameters())
            self.listener = listener

            // Set the service to advertise.
            listener.service = NWListener.Service(
                name: name,
                type: AutomergeSyncProtocol.bonjourType,
                txtRecord: document.id.uuidString.data(using: .utf8)
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

    func startListening() {
        listener?.stateUpdateHandler = listenerStateChanged

        // The system calls this when a new connection arrives at the listener.
        // Start the connection to accept it, or cancel to reject it.
        listener?.newConnectionHandler = { [weak self] newConnection in
            Logger.peerlistener
                .trace(
                    "New connection received from \(String(describing: newConnection.endpoint), privacy: .sensitive): \(newConnection.debugDescription, privacy: .public)"
                )
            self?.connections.append(newConnection)
            // FIXME: check to see if there's already a connection with the endpoint, and if so -
            // cancel the incoming connection:
            // newConnection.cancel()
        }

        // Start listening, and request updates on the main queue.
        listener?.start(queue: .main)
    }

    // Stop listening.
    func stopListening() {
        guard let listener else { return }
        listener.cancel()
        self.listener = nil
    }

    // Update the advertised name on the network.
    func resetName(_ name: String) {
        guard let document, let listener else { return }
        // Reset the service to advertise.
        listener.service = NWListener.Service(
            name: self.name,
            type: AutomergeSyncProtocol.bonjourType,
            txtRecord: document.id.uuidString.data(using: .utf8)
        )
        Logger.peerlistener
            .debug(
                "Updated bonjour network listener to name \(name, privacy: .sensitive) for document id \(document.id.uuidString, privacy: .public)"
            )
    }
}
