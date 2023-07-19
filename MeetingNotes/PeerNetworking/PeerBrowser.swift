/*
 Copyright © 2022 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 WWDC Video references aligned with this code:
 - https://developer.apple.com/videos/play/wwdc2019/713/
 - https://developer.apple.com/videos/play/wwdc2020/10110/
 */

import Network
import OSLog

final class PeerBrowser: ObservableObject {
    var browser: NWBrowser?

    @Published var browserResults: [NWBrowser.Result] = []
    @Published var browserStatus: NWBrowser.State

    init() {
        browserStatus = .setup
        startBrowsing()
    }

    // Start browsing for services.
    func startBrowsing() {
        // Create parameters, and allow browsing over a peer-to-peer link.
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        // Browse for the Automerge sync bonjour service type.
        let browser = NWBrowser(
            for: .bonjour(type: AutomergeSyncProtocol.bonjourType, domain: nil),
            using: parameters
        )
        self.browser = browser
        browser.stateUpdateHandler = { newState in
            Logger.peerbrowser.debug("State Update: \(String(describing: newState), privacy: .public)")
            switch newState {
            case let .failed(error):
                self.browserStatus = .failed(error)
                // Restart the browser if it loses its connection.
                if error == NWError.dns(DNSServiceErrorType(kDNSServiceErr_DefunctConnection)) {
                    Logger.peerbrowser.info("Browser failed with \(error, privacy: .public), restarting")
                    browser.cancel()
                    self.startBrowsing()
                } else {
                    Logger.peerbrowser.warning("Browser failed with \(error, privacy: .public), stopping")
                    browser.cancel()
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
        browser.browseResultsChangedHandler = { results, _ in
            Logger.peerbrowser.debug("\(results.count, privacy: .public) results provided.")
            self.browserResults = results.sorted(by: {
                $0.hashValue < $1.hashValue
            })
        }

        Logger.peerbrowser.debug("Activating NWBrowser \(browser.debugDescription, privacy: .public)")
        // Start browsing and ask for updates on the main queue.
        browser.start(queue: .main)
    }
}
