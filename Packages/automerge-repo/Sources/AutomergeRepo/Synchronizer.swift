import Automerge

protocol SyncThing: Sendable {
    func peers() -> [PEER_ID]
    func removePeer(peer: PEER_ID)
    func addPeer(peer: PEER_ID)
    func addDoc(doc: DocumentId)
    func removeDoc(doc: DocumentId)
    func receiveMsg(msg: SyncV1Msg)
}

// CollectionSynchronizer
//  - multiple DocumentSynchronizers

struct CollectionSynchronizer: Sendable {
    private var docSynchronizers: [DocumentId: DocSynchronizer]
    private var _peers: Set<PEER_ID>

    init() {
        self.docSynchronizers = [:]
        self._peers = Set<PEER_ID>()
    }

    func peers() -> [PEER_ID] {
        Array(_peers)
    }

    func removePeer(peer _: PEER_ID) {}

    func addPeer(peer _: PEER_ID) {}

    func addDoc(doc _: DocumentId) {}

    func removeDoc(doc _: DocumentId) {}

    func receiveMsg(msg _: SyncV1Msg) {}
}

struct DocSynchronizer: Sendable {
    private var activePeers: [PEER_ID]
    private var syncStarted = false
    private var handle: DocHandle
    private var syncState: SyncState

    func peers() -> [PEER_ID] {
        Array(activePeers)
    }

    // async syncWithPeers
    // async BroadcastToPeers(ephemeral)

    // sync collects up all the sync messages, one for each peer by SyncState, and then
    // sends them "en masse"

    // automerge-repo does an 'emit' message thing here - so this is uncoupled
    // from what receives the message

    // THIS DRIVES THE SYNC STATE MACHINE PORTION OF THE WebSocket network setup
    // So - other than doing the complicated emit' port thing (using Combine?) how does
    // the DocSynchronizer know about the NetworkSubsystem in order to be able to send and receive packets?
    // What wires up that connection?

    func removePeer(peer _: PEER_ID) {}

    func addPeer(peer _: PEER_ID) {}

    func addDoc(doc _: DocumentId) {}

    func removeDoc(doc _: DocumentId) {}

    func receiveMsg(msg _: SyncV1Msg) {}
}
