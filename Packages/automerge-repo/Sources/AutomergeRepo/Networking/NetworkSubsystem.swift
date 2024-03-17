import AsyncAlgorithms
import Automerge
import struct Foundation.Data
import OSLog
import PotentCBOR

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts

/// A type that hosts network subsystems to connect to peers.
///
/// The NetworkSubsystem instance is responsible for setting up and configuring any network providers, and responding to
/// messages from remote peers after the connection has been established. The connection handshake and peer negotiation
/// is
/// the responsibility of the network provider instance.
public actor NetworkSubsystem {
    // a list of documents with a pending request for a documentId
    var requestedDocuments: [DocumentId: [PEER_ID]] = [:]

    public static let encoder = CBOREncoder()
    public static let decoder = CBORDecoder()

    // repo is a weak var to avoid a retain cycle - a network subsystem is
    // (so far) always created with a Repo and uses it for remote data storage of documents that
    // it fetches, syncs, or gossips about.
    //
    // TODO: revisit this and consider if the callbacks to repo should be exposed as a delegate
    weak var repo: Repo?
    var adapters: [any NetworkProvider]
    let combinedNetworkEvents: AsyncChannel<NetworkAdapterEvents>
    var _backgroundNetworkReaderTasks: [Task<Void, Never>] = []

    init() {
        self.adapters = []
        combinedNetworkEvents = AsyncChannel()
    }

    func linkRepo(_ repo: Repo) async {
        self.repo = repo
    }

    func addAdapter(adapter: some NetworkProvider) async {
        guard let repo else {
            fatalError("NO REPO CONFIGURED WHEN ADDING ADAPTERS")
        }
        adapter.setDelegate(something: self)
        self.adapters.append(adapter)
        await adapter.connect(asPeer: repo.peerId, localMetaData: repo.localPeerMetadata)
        // adapter's peer metadata is set after connect returns
        await repo.addPeerWithMetadata(peer: adapter.connectedPeer, metadata: adapter.peerMetadata)
    }

    func startRemoteFetch(id: DocumentId) async throws {
        // attempt to fetch the provided document Id from all peers, returning the document
        // or returning nil if the document is unavailable.
        // Save the throwing scenarios for failures in connection, etc.
        guard let repo else {
            // invariant that there should be a valid doc handle available from the repo
            fatalError("DocHandle isn't available from the repo")
        }

        try await allNetworksReady()
        let newDocument = Document()
        for adapter in adapters {
            // upsert the requested document into the list by peer
            if var existingList = requestedDocuments[id] {
                existingList.append(adapter.connectedPeer)
                requestedDocuments[id] = existingList
            } else {
                requestedDocuments[id] = [adapter.connectedPeer]
            }
            let syncState = await repo.syncState(id: id, peer: adapter.connectedPeer)
            if let syncRequestData = newDocument.generateSyncMessage(state: syncState) {
                await adapter.send(message: .request(SyncV1Msg.RequestMsg(
                    documentId: id.description,
                    senderId: adapter.peerId,
                    targetId: adapter.connectedPeer,
                    sync_message: syncRequestData
                )))
            }
        }
    }

    func broadcast(message: SyncV1Msg) async {
        for n in adapters {
            await n.send(message: message)
        }
    }

    func send(message: SyncV1Msg, to: PEER_ID) async {
        if let adapter = adapters.first(where: { provider in
            provider.connectedPeer == to
        }) {
            await adapter.send(message: message)
        }
    }

    // async waits until underlying networks are connected and ready to send and receive messages
    // (aka all networks are connected and "peered")
    func isReady() async -> Bool {
        for adapter in adapters {
            if await !adapter.ready() {
                return false
            }
        }
        return true
    }

    func allNetworksReady() async throws {
        var currentlyReady = await self.isReady()
        while currentlyReady != true {
            try await Task.sleep(for: .milliseconds(500))
            currentlyReady = await self.isReady()
        }
    }
}

extension NetworkSubsystem: NetworkEventReceiver {
    // Collection point for messages coming in from all network adapters.
    // The network subsystem forwards messages from network peers to the relevant places,
    // and forwards messages out to peers as needed
    //
    // In automerge-repo code, it appears to update information on an ephemeral information (
    // a sort of middleware) before emitting it upwards.
    public func receiveEvent(event: NetworkAdapterEvents) async {
        guard let repo else {
            // No-op if there's no repo to update state or handle
            // further message passing
            return
        }
        switch event {
        case .ready:
            break
        case .close:
            break
        // attempt to reconnect, or remove from active adapters?
        case let .peerCandidate(payload):
            await repo.addPeerWithMetadata(peer: payload.peerId, metadata: payload.peerMetadata)
        case let .peerDisconnect(payload):
            await repo.removePeer(peer: payload.peerId)
        case let .message(payload):
            switch payload {
            case .peer, .join, .leave, .unknown:
                // ERROR FOR THESE MSG TYPES - expected to be handled at adapter
                Logger.network
                    .error(
                        "Unexpected message type received by network subsystem: \(payload.debugDescription, privacy: .public)"
                    )
                #if DEBUG
                fatalError("UNEXPECTED MSG")
                #endif
            case let .error(errorMsg):
                Logger.network
                    .warning(
                        "Error message received by network subsystem: \(errorMsg.debugDescription, privacy: .public)"
                    )
            case let .request(requestMsg):
                await repo.handleRequest(msg: requestMsg)
            case let .sync(syncMsg):
                await repo.handleSync(msg: syncMsg)
            case let .unavailable(unavailableMsg):
                guard let docId = DocumentId(unavailableMsg.documentId) else {
                    Logger.network
                        .error(
                            "Invalid message Id \(unavailableMsg.documentId, privacy: .public) in unavailable msg: \(unavailableMsg.debugDescription, privacy: .public)"
                        )
                    return
                }
                if let peersRequested = requestedDocuments[docId] {
                    // if we receive an unavailable from one peer, record it and wait until
                    // we receive unavailable from all available peers before marking it unavailable
                    let filtered = peersRequested.filter { peerId in
                        // include the peers OTHER than the one sending the unavailable msg
                        peerId != unavailableMsg.senderId
                    }
                    if filtered.isEmpty {
                        await repo.markDocUnavailable(id: docId)
                        requestedDocuments.removeValue(forKey: docId)
                    } else {
                        // save the data back for other adapters to respond later...
                        requestedDocuments[docId] = filtered
                    }
                } else {
                    // no peers are waiting to hear about a requested document, ignore
                    return
                }
            case let .ephemeral(ephemeralMsg):
                Logger.network
                    .error(
                        "UNIMPLEMENTED EPHEMERAL MESSAGE PASSING: \(ephemeralMsg.debugDescription, privacy: .public)"
                    )
            case let .remoteSubscriptionChange(remoteSubscriptionChangeMsg):
                Logger.network
                    .error(
                        "UNIMPLEMENTED EPHEMERAL MESSAGE PASSING: \(remoteSubscriptionChangeMsg.debugDescription, privacy: .public)"
                    )
            case let .remoteHeadsChanged(remoteHeadsChangedMsg):
                Logger.network
                    .error(
                        "UNIMPLEMENTED EPHEMERAL MESSAGE PASSING: \(remoteHeadsChangedMsg.debugDescription, privacy: .public)"
                    )
            }
        }
    }
}
