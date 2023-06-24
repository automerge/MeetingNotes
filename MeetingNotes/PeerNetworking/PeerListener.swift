/*
 Copyright © 2022 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 WWDC Video references aligned with this code:
 - https://developer.apple.com/videos/play/wwdc2019/713/
 - https://developer.apple.com/videos/play/wwdc2020/10110/
 - https://developer.apple.com/videos/play/wwdc2022/110339/

 */

import Network
import OSLog

var bonjourListener: PeerListener?
var applicationServiceListener: PeerListener?

class PeerListener {
    enum ServiceType {
        case bonjour
        case applicationService
    }

    weak var delegate: PeerConnectionDelegate?
    var listener: NWListener?
    var name: String?
    let passcode: String?
    let type: ServiceType
    let logger = Logger(subsystem: "PeerNetwork", category: "PeerListener")
    
    // Create a listener with a name to advertise, a passcode for authentication,
    // and a delegate to handle inbound connections.
    init(name: String, passcode: String, delegate: PeerConnectionDelegate) {
        type = .bonjour
        self.delegate = delegate
        self.name = name
        self.passcode = passcode
        setupBonjourListener()
    }

    // Create a listener that advertises the app's sync service
    // and has a delegate to handle inbound connections.
    init(delegate: PeerConnectionDelegate) {
        type = .applicationService
        self.delegate = delegate
        name = nil
        passcode = nil
        setupApplicationServiceListener()
    }

    func setupApplicationServiceListener() {
        do {
            // Create the listener object.
            let listener = try NWListener(using: applicationServiceParameters())
            self.listener = listener

            // Set the service to advertise.
            listener.service = NWListener.Service(applicationService: AutomergeSyncProtocol.applicationService)

            startListening()
        } catch {
            self.logger.critical("Failed to create application service listener")
            abort()
        }
    }

    // Start listening and advertising.
    func setupBonjourListener() {
        do {
            // When hosting a game via Bonjour, use the passcode and advertise the automerge sync service.
            guard let name = name, let passcode = passcode else {
                self.logger.error("Cannot create Bonjour listener without name and passcode")
                return
            }

            // Create the listener object.
            let listener = try NWListener(using: NWParameters(passcode: passcode))
            self.listener = listener

            // Set the service to advertise.
            listener.service = NWListener.Service(name: name, type: AutomergeSyncProtocol.bonjourType)

            startListening()
        } catch {
            self.logger.critical("Failed to create bonjour listener")
            abort()
        }
    }

    func bonjourListenerStateChanged(newState: NWListener.State) {
        switch newState {
        case .ready:
            logger.info("Listener ready on \(String(describing: self.listener?.port), privacy: .public)")
        case let .failed(error):
            if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                logger.warning("Listener failed with \(error, privacy: .public), restarting.")
                listener?.cancel()
                setupBonjourListener()
            } else {
                logger.error("Listener failed with \(error, privacy: .public), stopping.")
                delegate?.displayAdvertiseError(error)
                listener?.cancel()
            }
        case .cancelled:
            bonjourListener = nil
        default:
            break
        }
    }

    func applicationServiceListenerStateChanged(newState: NWListener.State) {
        switch newState {
        case .ready:
            logger.info("Listener ready for nearby devices")
        case let .failed(error):
            logger.error("Listener failed with \(error, privacy: .public), stopping.")
            delegate?.displayAdvertiseError(error)
            listener?.cancel()
        case .cancelled:
            applicationServiceListener = nil
        default:
            break
        }
    }

    func listenerStateChanged(newState: NWListener.State) {
        switch type {
        case .bonjour:
            bonjourListenerStateChanged(newState: newState)
        case .applicationService:
            applicationServiceListenerStateChanged(newState: newState)
        }
    }

    func startListening() {
        listener?.stateUpdateHandler = listenerStateChanged

        // The system calls this when a new connection arrives at the listener.
        // Start the connection to accept it, cancel to reject it.
        listener?.newConnectionHandler = { newConnection in
            if let delegate = self.delegate {
                if sharedConnection == nil {
                    // Accept a new connection.
                    sharedConnection = PeerConnection(connection: newConnection, delegate: delegate)
                } else {
                    // If a game is already in progress, reject it.
                    newConnection.cancel()
                }
            }
        }

        // Start listening, and request updates on the main queue.
        listener?.start(queue: .main)
    }

    // Stop listening.
    func stopListening() {
        if let listener = listener {
            listener.cancel()
            switch type {
            case .bonjour:
                bonjourListener = nil
            case .applicationService:
                applicationServiceListener = nil
            }
        }
    }

    // If the user changes their name, update the advertised name.
    func resetName(_ name: String) {
        guard type == .bonjour else {
            return
        }

        self.name = name
        if let listener = listener {
            // Reset the service to advertise.
            listener.service = NWListener.Service(name: self.name, type: "_tictactoe._tcp")
        }
    }
}
