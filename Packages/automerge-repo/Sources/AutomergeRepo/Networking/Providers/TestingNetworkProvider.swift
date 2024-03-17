import Automerge
import Foundation

public struct TestingNetworkProviderConfiguration: Sendable, CustomStringConvertible {
    let remotePeer: PEER_ID
    let remotePeerMetadata: PeerMetadata?
    let msgResponse: @Sendable (SyncV1Msg) async -> SyncV1Msg?

    public var description: String {
        "peer: \(remotePeer), metadata: \(remotePeerMetadata?.debugDescription ?? "none")"
    }

    init(
        remotePeer: PEER_ID,
        remotePeerMetadata: PeerMetadata?,
        msgResponse: @Sendable @escaping (SyncV1Msg) async -> SyncV1Msg
    ) {
        self.remotePeer = remotePeer
        self.remotePeerMetadata = remotePeerMetadata
        self.msgResponse = msgResponse
    }

    public static let simple: @Sendable (SyncV1Msg) async -> SyncV1Msg? = { msg in
        var doc = Document()
        var syncState = SyncState()
        let peerId: PEER_ID = "SIMPLE REMOTE TEST"
        let peerMetadata: PeerMetadata? = PeerMetadata(storageId: "SIMPLE STORAGE", isEphemeral: true)
        switch msg {
        case let .join(msg):
            return .peer(.init(
                senderId: peerId,
                targetId: msg.senderId,
                storageId: peerMetadata?.storageId,
                ephemeral: peerMetadata?.isEphemeral ?? false
            ))
        case .peer:
            return nil
        case .leave:
            return nil
        case .error:
            return nil
        case let .request(msg):
            // everything is always unavailable
            return .unavailable(.init(documentId: msg.documentId, senderId: peerId, targetId: msg.senderId))
        case let .sync(msg):
            do {
                try doc.receiveSyncMessage(state: syncState, message: msg.data)
                if let returnData = doc.generateSyncMessage(state: syncState) {
                    return .sync(.init(
                        documentId: msg.documentId,
                        senderId: peerId,
                        targetId: msg.senderId,
                        sync_message: returnData
                    ))
                }
            } catch {
                return .error(.init(message: error.localizedDescription))
            }
            return nil
        case .unavailable:
            return nil
        case .ephemeral:
            return nil // TODO: RESPONSE EXAMPLE
        case .remoteSubscriptionChange:
            return nil
        case .remoteHeadsChanged:
            return nil
        case .unknown:
            return nil
        }
    }
}

struct UnconfiguredTestNetwork: LocalizedError {}

// this could be @MainActor public final class - or 'actor'
public actor TestingNetworkProvider: NetworkProvider {
    public nonisolated var id: PEER_ID {
        "testNetworkPeer"
    }

    public nonisolated var description: String {
        "TestNetwork"
    }

    public var localPeerId: PEER_ID
    private var localMetaData: PeerMetadata?

    var delegate: (any NetworkEventReceiver)?

    var config: TestingNetworkProviderConfiguration?
    var connected: Bool
    var messages: [SyncV1Msg] = []

    public typealias ProviderConfiguration = TestingNetworkProviderConfiguration

    init(id: PEER_ID, metadata: PeerMetadata?) {
        self.localPeerId = id
        self.localMetaData = metadata
        self.connected = false
        self.delegate = nil
    }

    public func configure(_ config: TestingNetworkProviderConfiguration) async {
        self.config = config
    }

    public var peerId: PEER_ID {
        self.localPeerId
    }

    public var peerMetadata: PeerMetadata? {
        get async {
            if let config = self.config, self.connected == true {
                return config.remotePeerMetadata
            }
            return nil
        }
    }

    public var connectedPeer: PEER_ID? {
        get async {
            if let config = self.config, self.connected == true {
                return config.remotePeer
            }
            return nil
        }
    }

    public func connect(asPeer _: PEER_ID, localMetaData _: PeerMetadata?) async throws {
        do {
            guard let config = self.config else {
                throw UnconfiguredTestNetwork()
            }
            await self.delegate?.receiveEvent(
                event: .peerCandidate(
                    payload: .init(
                        peerId: config.remotePeer,
                        peerMetadata: config.remotePeerMetadata
                    )
                )
            )
            try await Task.sleep(for: .milliseconds(250))
            await self.delegate?.receiveEvent(event: .ready)
            self.connected = true

        } catch {
            self.connected = false
        }
    }

    public func disconnect() async {
        self.connected = false
    }

    public func ready() async -> Bool {
        self.connected
    }

    public func send(message: SyncV1Msg) async {
        self.messages.append(message)
        if let response = await config?.msgResponse(message) {
            await delegate?.receiveEvent(event: .message(payload: response))
        }
    }

    public func setDelegate(something: any NetworkEventReceiver) async {
        self.delegate = something
    }

    // MARK: TESTING SPECIFIC API

    public func disconnectNow() async {
        guard let config = self.config else {
            fatalError("Attempting to disconnect an unconfigured testing network")
        }
        if self.connected {
            self.connected = false
            await delegate?.receiveEvent(event: .peerDisconnect(payload: .init(peerId: config.remotePeer)))
        }
    }

    public func messagesReceivedByRemotePeer() async -> [SyncV1Msg] {
        self.messages
    }

    /// WIPES TEST NETWORK AND ERASES DELEGATE SETTING
    public func resetTestNetwork() async {
        guard self.config != nil else {
            fatalError("Attempting to reset an unconfigured testing network")
        }
        self.connected = false
        self.messages = []
        self.delegate = nil
    }
}
