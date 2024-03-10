

import Automerge
import Foundation

// @globalActor
public actor Repo {
//    public static let shared = Repo()
    public let peerId: PEER_ID
    // to replace DocumentSyncCoordinator
    private var _handles: [DocumentId: DocHandle]
    private var storage: StorageProvider?
    private var network: NetworkSubsystem
    // saveDebounceRate = 100
    private var synchronizer: CollectionSynchronizer
    var sharePolicy: any SharePolicy

    /** maps peer id to to persistence information (storageId, isEphemeral), access by collection synchronizer  */
    /** @hidden */
    var peerMetadataByPeerId: [PEER_ID: PeerMetadata]

//    #remoteHeadsSubscriptions = new RemoteHeadsSubscriptions()
//    export class RemoteHeadsSubscriptions extends EventEmitter<RemoteHeadsSubscriptionEvents> {
//      // Storage IDs we have received remote heads from
//      #knownHeads: Map<DocumentId, Map<StorageId, LastHeads>> = new Map()
    // ^^^ DUPLICATES DATA stored in DocHandle...

//      // Storage IDs we have subscribed to via Repo.subscribeToRemoteHeads
//      #ourSubscriptions: Set<StorageId> = new Set()

//      // Storage IDs other peers have subscribed to by sending us a control message
//      #theirSubscriptions: Map<StorageId, Set<PeerId>> = new Map()

//      // Peers we will always share remote heads with even if they are not subscribed
//      #generousPeers: Set<PeerId> = new Set()

//      // Documents each peer has open, we need this information so we only send remote heads of documents that the
//      /peer knows
//      #subscribedDocsByPeer: Map<PeerId, Set<DocumentId>> = new Map()

    private var remoteHeadsGossipingEnabled = false

    init(
        storage: StorageProvider? = nil,
        networkAdapters: [any NetworkProvider] = [],
        sharePolicy: some SharePolicy
    ) async {
        self.peerId = UUID().uuidString
        self._handles = [:]
        self.peerMetadataByPeerId = [:]
        self.storage = storage
        self.network = await NetworkSubsystem(adapters: networkAdapters)
        self.sharePolicy = sharePolicy
        self.synchronizer = CollectionSynchronizer()
    }

    // possible functions for dynamic configuration of a shared repo
//    public func setStorageAdapter(storage: some StorageProvider) {
//
//    }
//
//    public func addNetworkAdapter(net: some NetworkProvider) {
//        network.adapters.append(net)
//    }
//
//    public func removeNetworkAdapter(net: some NetworkProvider) {
//        network.adapters.removeAll { provider in
//            provider.id == net.id
//        }
//    }

    public func handles() async -> [DocHandle] {
        Array(_handles.values)
    }

    public func peers() async -> [PEER_ID] {
        []
    }

    public func getStorageIdOfPeer(peer _: PEER_ID) async -> STORAGE_ID? {
        nil
    }

    public func create(doc: Document) async -> DocHandle {
        DocHandle(id: DocumentId(), isNew: true, initialValue: doc)
    }

    public func create(data: Data) async throws -> DocHandle {
        try DocHandle(id: DocumentId(), isNew: true, initialValue: Document(data))
    }

    /// Returns a ready docHandle with a loaded Document or throws an error in the attempt of it.
    /// - Parameter handle: The handle to resolve
    func resolveHandle(handle: DocHandle) async throws -> DocHandle {
        // generally of the idea that we'll drive DocHandle state updates from within Repo
        // and these async methods
        guard !handle.isDeleted else {
            throw Errors.DocDeleted(id: handle.id)
        }
        guard !handle.isUnavailable else {
            throw Errors.DocUnavailable(id: handle.id)
        }

        return handle
    }

    public func clone(id: DocumentId) async throws -> DocHandle {
        guard let originalDocHandle = _handles[id] else {
            throw Errors.Unavailable(id: id)
        }
        let resolvedHandle = try await self.resolveHandle(handle: originalDocHandle)
        // this would feel a lot nicer if it was try await _handles.resolve()

        if let originalDoc = resolvedHandle.value {
            let fork = originalDoc.fork()
            let newId = DocumentId()
            let newHandle = DocHandle(id: newId, isNew: true, initialValue: fork)
            _handles[newId] = newHandle
            return newHandle
        } else {
            throw Errors.BigBadaBoom(msg: "DocHandle(\(id) doesn't have a value")
        }
    }

    public func find(id: DocumentId) async throws -> DocHandle {
        // generally of the idea that we'll drive DocHandle state updates from within Repo
        // and these async methods
        DocHandle(id: id, isNew: false)
        // TODO: attempt to load, failing that, req from network
    }

    public func delete(id: DocumentId) async throws {
        guard var originalDocHandle = _handles[id] else {
            throw Errors.Unavailable(id: id)
        }
        originalDocHandle.state = .deleted
        originalDocHandle.value = nil
    }

    public func export(id _: DocumentId) async throws -> Data {
        Data()
    }

    public func `import`(data _: Data) async {}

    public func subscribeToRemotes(remotes _: [STORAGE_ID]) async {}

    public func storageId() async -> STORAGE_ID? {
        storage?.id
    }
}

// REPO
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/Repo.ts
// - looks like it's the rough equivalent to the overall synchronization coordinator

// - owns synchronizer, network, and storage subsystems
// - it "just" manages the connections, adds, and removals - when documents "appear", they're
// added to the synchronizer, which is the thing that accepts sync messages and tries to keep documents
// up to date with any registered peers. It emits (at a debounced rate) events to let anyone watching
// a document know that changes have occurred.
//
// Looks like it also has the idea of a sharePolicy per document, and if provided, then a document
// will be shared with peers (or positively respond to requests for the document if it's requested)

// Repo
//  property: peers [PeerId] - all (currently) connected peers
//  property: handles [DocHandle] - list of all the DocHandles
// - func clone(DocHandle) -> DocHandle
// - func export(DocumentId) -> uint8[]
// - func import(uint8[]) -> DocHandle
// - func create() -> DocHandle
// - func find(DocumentId) -> DocHandle
// - func delete(DocumentId)
// - func storageId() -> StorageId (async)
// - func storageIdForPeer(peerId) -> StorageId
// - func subscribeToRemotes([StorageId])
