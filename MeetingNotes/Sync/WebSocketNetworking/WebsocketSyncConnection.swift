import Automerge
import Combine
import Foundation
import OSLog
import PotentCBOR

/// A class that provides a WebSocket connection to sync an Automerge document.
public final class WebsocketSyncConnection: ObservableObject {
    /// The state of the WebSocket sync connection.
    public enum SyncProtocolState {
        /// A sync connection hasn't yet been requested
        case newConnection
        /// The state is initiating and waiting to successfully peer with the recipient.
        case initiating
        /// The connection has successfully peered.
        ///
        /// While `peered`, the connection can send and receive sync, ephemeral, and gossip messages about remote peers.
        case peered
        /// The connection has terminated.
        case closed
    }

    static let fileEncoder = CBOREncoder()
    static let fileDecoder = CBORDecoder()
    private var webSocketTask: URLSessionWebSocketTask?
    private let senderId: String
    private let targetId: String? = nil
    private weak var document: Automerge.Document?

    @Published public var syncState: SyncProtocolState

    init(_ document: Automerge.Document? = nil) {
        syncState = .newConnection
        senderId = UUID().uuidString
        self.document = document
    }

    public func registerDocument(_ document: Automerge.Document) {
        self.document = document
    }

    /// Initiates a WebSocket connection to a remote peer.
    public func connect(_ destination: String) {
        assert(syncState == .newConnection || syncState == .closed)
        if self.document == nil {
            Logger.webSocket.error("Attempting to join a connection without a document registered")
            return
        }
        guard let url = URL(string: destination) else {
            Logger.webSocket.error("Destination provided is not a valid URL")
            return
        }
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        // establishes the websocket
        Logger.webSocket.trace("Activating websocket to \(url, privacy: .public)")
        configureWebsocketReceiveHandler()
        guard let webSocketTask = webSocketTask else {
            #if DEBUG
            fatalError("Attempting to configure and join a nil webSocketTask")
            #else
            return
            #endif
        }
        webSocketTask.resume()
        let joinMessage = JoinMsg(senderId: senderId)
        do {
            let data = try Self.fileEncoder.encode(joinMessage)
            webSocketTask.send(.data(data)) { [weak self] error in
                if let error = error {
                    Logger.webSocket.warning("\(error.localizedDescription, privacy: .public)")
                    // kill the websocket and disconnect
                    self?.webSocketTask = nil
                    self?.syncState = .closed
                    // should we have a syncState = .failed?
                }
            }
            syncState = .initiating
        } catch {
            Logger.webSocket.error("\(error.localizedDescription, privacy: .public)")
            syncState = .closed
            self.webSocketTask = nil
        }
    }

    public func disconnect() {
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        syncState = .closed
        self.webSocketTask = nil
    }

    private func configureWebsocketReceiveHandler() {
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
                //
                // self.messages.append(text)
                case let .data(data):
                    // Handle binary data
                    Logger.webSocket.warning("RCVD: .data(\(data.hexEncodedString(uppercase: false)))")
                    if let peerMsg = self.attemptDecodePeer(data: data) {
                        Logger.webSocket.info("DECODED PEER MSG")
                        dump(peerMsg)
                    } else if let errorMsg = self.attemptDecodeError(data: data) {
                        Logger.webSocket.info("DECODED ERROR MSG")
                        dump(errorMsg)
                    } else {
                        Logger.webSocket.warning("FAILED TO DECODE MSG")
                    }
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

                    // with sync.automerge.org:

                // {
                //   "type": "peer",
                //   "senderId": "storage-server-sync-automerge-org",
                //   "peerMetadata": {"storageId": "3760df37-a4c6-4f66-9ecd-732039a9385d", "isEphemeral": false},
                //   "selectedProtocolVersion": "1",
                //   "targetId": "FA38A1B2-1433-49E7-8C3C-5F63C117DF09"
                // }
                @unknown default:
                    break
                }
            }
        }
    }

    private func attemptDecodePeer(data: Data) -> PeerMsg? {
        do {
            return try Self.fileDecoder.decode(PeerMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as PeerMsg")
        }
        return nil
    }

    private func attemptDecodeError(data: Data) -> ErrorMsg? {
        do {
            return try Self.fileDecoder.decode(ErrorMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as ErrorMsg")
        }
        return nil
    }

//    func sendMessage(_ message: String) {
//        // guard let data = message.data(using: .utf8) else { return }
//        webSocketTask?.send(.string(message)) { error in
//            if let error = error {
//                print(error.localizedDescription)
//            }
//        }
//    }
}
