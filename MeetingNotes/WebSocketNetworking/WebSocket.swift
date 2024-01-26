import Combine
import Foundation
import OSLog
import PotentCBOR

// base WebSocket usage example from https://medium.com/@ios_guru/swiftui-and-websocket-connectivity-478aa5fddfc7
// Automerge Repo WebSocket sync details:
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo-network-websocket/README.md
// explicitly using a protocol version '1' here - make sure to specify that
// Send 'join', expect 'peer' in response - anything else, error
// 'request' or 'sync' to begin a sync
// receive 'unavailable' - nothing to sync/not found (aka 404)
// 'error' indicates an error
// 'ephemeral' for ? not obvious what its used for from the page
//

final class Websocket: ObservableObject {
    @Published var messages = [String]()
    static let fileEncoder = CBOREncoder()
    static let fileDecoder = CBORDecoder()

    private var webSocketTask: URLSessionWebSocketTask?

    init() {}

    // call first - then call join()
    public func connect() {
        guard let url = URL(string: "ws://localhost:3030/") else {
            Logger.webSocket.error("Unable to establish initial URL")
            return
        }
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        // establishes the websocket
        Logger.webSocket.trace("Activating websocket to \(url, privacy: .public)")
        webSocketTask?.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        webSocketTask?.receive { result in
            Logger.webSocket.trace("Received websocket message")
            switch result {
            case let .failure(error):
                Logger.webSocket.warning("RCVD: .failure(\(error.localizedDescription)")
                print(error.localizedDescription)
            case let .success(message):
                switch message {
                case let .string(text):
                    Logger.webSocket.warning("RCVD: .string(\(text)")
                    self.messages.append(text)
                case let .data(data):
                    // Handle binary data
                    Logger.webSocket.warning("RCVD: .data(\(data.hexEncodedString(uppercase: false)))")
                    // dumping data to logger in a format to fill in the right side of the utility
                    // https://cbor.me
                    // Resulting data packet (decoded):
                    // D9 DFFF                                 # tag(57343)
                    // 86                                   # array(6)
                    //  19 E000                           # unsigned(57344)
                    //  84                                # array(4)
                    //     64                             # text(4)
                    //        74797065                    # "type"
                    //     68                             # text(8)
                    //        73656E6465724964            # "senderId"
                    //     77                             # text(23)
                    //        73656C656374656450726F746F636F6C56657273696F6E # "selectedProtocolVersion"
                    //     68                             # text(8)
                    //        7461726765744964            # "targetId"
                    //  64                                # text(4)
                    //     70656572                       # "peer"
                    //  76                                # text(22)
                    //     73746F726167652D7365727665722D53706172726F77 # "storage-server-Sparrow"
                    //  61                                # text(1)
                    //     31                             # "1"
                    //  78 24                             # text(36)
                    //     41374535464645392D383333452D343430432D383739302D463046453432363131444532 #
                    //     "A7E5FFE9-833E-440C-8790-F0FE42611DE2"

                    // which maps to:

                // 57343([57344, ["type", "senderId", "selectedProtocolVersion", "targetId"], "peer",
                // "storage-server-Sparrow", "1", "A7E5FFE9-833E-440C-8790-F0FE42611DE2"])
                // dump(data)
                @unknown default:
//                    Logger.webSocket.error("Unknown case result: \(result)")
                    break
                }
            }
        }
    }

//    func sendMessage(_ message: String) {
//        // guard let data = message.data(using: .utf8) else { return }
//        webSocketTask?.send(.string(message)) { error in
//            if let error = error {
//                print(error.localizedDescription)
//            }
//        }
//    }

    func join(senderId: String) {
        guard let webSocketTask = webSocketTask else {
            #if DEBUG
            fatalError("Attempting to join on an nil webSocketTask")
            #else
            return
            #endif
        }
        let joinMessage = JoinMsg(senderId: senderId)
        do {
            let data = try Self.fileEncoder.encode(joinMessage)
            webSocketTask.send(.data(data)) { error in
                if let error = error {
                    print(error.localizedDescription)
                }
            }
        } catch {
            fatalError()
        }
    }
}
