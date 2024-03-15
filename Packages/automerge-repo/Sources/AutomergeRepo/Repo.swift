

import Automerge
import Foundation

// @globalActor
public actor Repo<S: StorageProvider> {
//    public static let shared = Repo()
    public let peerId: PEER_ID
    // to replace DocumentSyncCoordinator
    private var handles: [DocumentId: DocHandle]
    private var storage: DocumentStorage<S>?
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
        storageProvider: S? = nil,
        networkAdapters: [any NetworkProvider] = [],
        sharePolicy: some SharePolicy
    ) async {
        self.peerId = UUID().uuidString
        self.handles = [:]
        self.peerMetadataByPeerId = [:]
        if let provider = storageProvider {
            self.storage = DocumentStorage(provider)
        } else {
            self.storage = nil
        }
        let metadata = await PeerMetadata(storageId: storage?.id, isEphemeral: storageProvider == nil)
        self.network = await NetworkSubsystem(adapters: networkAdapters, peerId: self.peerId, metadata: metadata)
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

//    public func handles() async -> [DocHandle] {
//        Array(_handles.values)
//    }

    public func peers() async -> [PEER_ID] {
        []
    }

    public func getStorageIdOfPeer(peer _: PEER_ID) async -> STORAGE_ID? {
        nil
    }

    public func create(doc: Document) async throws -> Document {
        let handle = DocHandle(id: DocumentId(), loadFetch: false, initialValue: doc)
        self.handles[handle.id] = handle
        return try await resolveDocHandle(id: handle.id)
    }

    public func create(data: Data) async throws -> Document {
        let handle = DocHandle(id: DocumentId(), loadFetch: false, initialValue: try Document(data))
        self.handles[handle.id] = handle
        return try await resolveDocHandle(id: handle.id)
    }

    public func clone(id: DocumentId) async throws -> Document {
        let originalDoc = try await resolveDocHandle(id: id)
        let fork = originalDoc.fork()
        let newId = DocumentId()
        let newHandle = DocHandle(id: newId, loadFetch: false, initialValue: fork)
        handles[newId] = newHandle
        return try await resolveDocHandle(id: newId)
    }

    public func find(id: DocumentId) async throws -> Document {
        // generally of the idea that we'll drive DocHandle state updates from within Repo
        // and these async methods
        let handle: DocHandle
        if let knownHandle = handles[id] {
            handle = knownHandle
        } else {
            let newHandle = DocHandle(id: id, loadFetch: true)
            handles[id] = newHandle
            handle = newHandle
        }
        return try await resolveDocHandle(id: handle.id)
    }

    public func delete(id: DocumentId) async throws {
        guard var originalDocHandle = handles[id] else {
            throw Errors.Unavailable(id: id)
        }
        originalDocHandle.state = .deleted
        originalDocHandle._doc = nil
    }

    public func export(id _: DocumentId) async throws -> Data {
        Data()
    }

    public func `import`(data _: Data) async {}

    public func subscribeToRemotes(remotes _: [STORAGE_ID]) async {}

    public func storageId() async -> STORAGE_ID? {
        await storage?.id
    }
    
    // MARK: Methods to resolve docHandles
    
    func resolveDocHandle(id: DocumentId) async throws -> Document {
        if var handle = handles[id] {
            switch handle.state {
            case .idle:
//                if handle.
                handle.state = .loading
                handles[id] = handle
                return try await resolveDocHandle(id: id)
            case .loading:
                if let doc = try await loadFromStorage(id: id) {
                    handle.state = .ready
                    handles[id] = handle
                    return doc
                } else {
                    handle.state = .requesting
                    handles[id] = handle
                    return try await resolveDocHandle(id: id)
                }
            case .requesting:
                fatalError("NOT IMPLEMENTED")
            case .ready:
                guard let doc = handle._doc else { fatalError("DocHandle state is ready, but ._doc is null") }
                return doc
            case .unavailable:
                throw Errors.DocUnavailable(id: handle.id)
            case .deleted:
                throw Errors.DocDeleted(id: handle.id)
            }
        } else {
            throw Errors.DocUnavailable(id: id)
        }
    }

    func loadFromStorage(id: DocumentId) async throws -> Document? {
        guard let storage = self.storage else {
            return nil
        }
        return try await storage.loadDoc(id: id)
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
// - func clone(Document) -> Document
// - func export(DocumentId) -> uint8[]
// - func import(uint8[]) -> Document
// - func create() -> Document
// - func find(DocumentId) -> Document
// - func delete(DocumentId)
// - func storageId() -> StorageId (async)
// - func storageIdForPeer(peerId) -> StorageId
// - func subscribeToRemotes([StorageId])
