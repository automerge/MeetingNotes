import AsyncAlgorithms
import Automerge
import struct Foundation.Data
import PotentCBOR

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts

/// A type that hosts network subsystems to connect to peers.
///
/// The NetworkSubsystem instance is responsible for setting up and configuring any network providers, and responding to
/// messages from remote peers after the connection has been established. The connection handshake and peer negotiation
/// is
/// the responsibility of the network provider instance.
public actor NetworkSubsystem: NetworkEventReceiver {
    public func receiveEvent(event _: NetworkAdapterEvents) async {}

    var requestedDocuments: [DocumentId] = []
    // store the sync state in the dochandle on Repo? Get it from there...
    var syncProviderForPeer: [PEER_ID: SyncState] = [:]

    public static let encoder = CBOREncoder()
    public static let decoder = CBORDecoder()

    weak var repo: Repo? = nil
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
        requestedDocuments.append(id)
        try await allNetworksReady()
        for adapter in adapters {
            let syncState = SyncState()
            syncProviderForPeer[adapter.connectedPeer] = syncState
            let newDocument = Document()
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

    func send(message: SyncV1Msg) async {
        // send any message to ALL adapters (is this right?)
        for n in adapters {
            await n.send(message: message)
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

    // combine version
    // import class Combine.PassthroughSubject
//    let eventPublisher: PassthroughSubject<NetworkAdapterEvents, Never> = PassthroughSubject()
}

// Collection point for all messages coming in, and going out, of the repository
// it forwards messages from network peers into the relevant places, and forwards messages
// out to peers as needed
//
// In automerge-repo code, it appears to update information on an ephemeral information (
// a sort of middleware) before emitting it upwards.
//
// Expected message types to forward:
//    isSyncMessage(message) ||
//    isEphemeralMessage(message) ||
//    isRequestMessage(message) ||
//    isDocumentUnavailableMessage(message) ||
//    isRemoteSubscriptionControlMessage(message) ||
//    isRemoteHeadsChanged(message)
//

// It also hosts peer to peer network components to allow for browsing and selection of connection,
// as well as potentially an "autoconnect" mode for P2P
