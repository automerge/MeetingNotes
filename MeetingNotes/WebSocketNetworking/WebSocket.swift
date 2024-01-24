import Combine
import Foundation
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

class Websocket: ObservableObject {
    @Published var messages = [String]()
    static let fileEncoder = CBOREncoder()
    static let fileDecoder = CBORDecoder()

    private var webSocketTask: URLSessionWebSocketTask?

    init() {
        self.connect()
    }

    private func connect() {
        guard let url = URL(string: "ws://localhost:3030/") else { return }
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        // establishes the websocket
        webSocketTask?.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        webSocketTask?.receive { result in
            switch result {
            case let .failure(error):
                print(error.localizedDescription)
            case let .success(message):
                switch message {
                case let .string(text):
                    self.messages.append(text)
                case let .data(data):
                    // Handle binary data
                    dump(data)
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    func sendMessage(_ message: String) {
        // guard let data = message.data(using: .utf8) else { return }
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print(error.localizedDescription)
            }
        }
    }

    func join(senderId: String) {
        let joinMessage = JoinMsg(senderId: senderId)
        do {
            let data = try Self.fileEncoder.encode(joinMessage)
            webSocketTask?.send(.data(data)) { error in
                if let error = error {
                    print(error.localizedDescription)
                }
            }
        } catch {
            fatalError()
        }
    }
}
