

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
//    public func addNetworkAdapter(net: some NetworkProvider) {
//        network.adapters.append(net)
//    }
//
//    public func removeNetworkAdapter(net: some NetworkProvider) {
//        network.adapters.removeAll { provider in
//            provider.id == net.id
//        }
//    }

    public func documentIds() async -> [DocumentId] {
        handles.values
            .filter { handle in
                handle.state == .ready || handle.state == .loading || handle.state == .requesting
            }
            .map(\.id)
    }

    /// Returns a list of the ids of available peers.
    public func peers() async -> [PEER_ID] {
        peerMetadataByPeerId.keys.sorted()
    }

    /// Returns the storage Id of for the id of the peer that you provide.
    /// - Parameter peer: The peer to request
    public func getStorageIdOfPeer(peer: PEER_ID) async -> STORAGE_ID? {
        if let metaForPeer = peerMetadataByPeerId[peer] {
            metaForPeer.storageId
        } else {
            nil
        }
    }

    /// Creates a new Automerge document, storing it and sharing the creation with connected peers.
    /// - Returns: The Automerge document.
    public func create() async throws -> Document {
        let handle = DocHandle(id: DocumentId(), isNew: true, initialValue: Document())
        self.handles[handle.id] = handle
        return try await resolveDocHandle(id: handle.id)
    }

    /// Creates a new Automerge document, storing it and sharing the creation with connected peers.
    /// - Parameter doc: The Automerge document to use for the new, shared document
    /// - Returns: The Automerge document.
    public func create(doc: Document) async throws -> Document {
        let handle = DocHandle(id: DocumentId(), isNew: true, initialValue: doc)
        self.handles[handle.id] = handle
        return try await resolveDocHandle(id: handle.id)
    }

    /// Creates a new Automerge document, storing it and sharing the creation with connected peers.
    /// - Parameter data: The data to load as an Automerge document for the new, shared document.
    /// - Returns: The Automerge document.
    public func create(data: Data) async throws -> Document {
        let handle = try DocHandle(id: DocumentId(), isNew: true, initialValue: Document(data))
        self.handles[handle.id] = handle
        return try await resolveDocHandle(id: handle.id)
    }

    /// Clones a document the repo already knows to create a new, shared document.
    /// - Parameter id: The id of the document to clone.
    /// - Returns: The Automerge document.
    public func clone(id: DocumentId) async throws -> Document {
        let originalDoc = try await resolveDocHandle(id: id)
        let fork = originalDoc.fork()
        let newId = DocumentId()
        let newHandle = DocHandle(id: newId, isNew: false, initialValue: fork)
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
            let newHandle = DocHandle(id: id, isNew: false)
            handles[id] = newHandle
            handle = newHandle
        }
        return try await resolveDocHandle(id: handle.id)
    }

    /// Deletes an automerge document from the repo.
    /// - Parameter id: The id of the document to remove.
    ///
    /// > NOTE: deletes do not propagate to connected peers.
    public func delete(id: DocumentId) async throws {
        guard var originalDocHandle = handles[id] else {
            throw Errors.Unavailable(id: id)
        }
        originalDocHandle.state = .deleted
        originalDocHandle._doc = nil
        handles[id] = originalDocHandle
        Task.detached {
            try await self.purgeFromStorage(id: id)
        }
    }

    /// Export the data associated with an Automerge document from the repo.
    /// - Parameter id: The id of the document to export.
    /// - Returns: The latest, compacted data of the Automerge document.
    public func export(id: DocumentId) async throws -> Data {
        let doc = try await self.resolveDocHandle(id: id)
        return doc.save()
    }

    /// Imports data as a new Automerge document
    /// - Parameter data: The data to import as an Automerge document
    /// - Returns: The id of the document that was created on import.
    public func `import`(data: Data) async throws -> DocumentId {
        let handle = try DocHandle(id: DocumentId(), isNew: true, initialValue: Document(data))
        self.handles[handle.id] = handle
        Task.detached {
            let _ = try await self.resolveDocHandle(id: handle.id)
        }
        return handle.id
    }

    public func subscribeToRemotes(remotes _: [STORAGE_ID]) async {}

    /// The storage id of this repo, if any.
    /// - Returns: The storage id from the repo's storage provider or nil.
    public func storageId() async -> STORAGE_ID? {
        await storage?.id
    }

    // MARK: Methods to resolve docHandles

    private func resolveDocHandle(id: DocumentId) async throws -> Document {
        if var handle = handles[id] {
            switch handle.state {
            case .idle:
                // default path with no other detail should probably route through loading
                handle.state = .loading
                handles[id] = handle
                return try await resolveDocHandle(id: id)
            case .loading:
                // Do we have the document
                if let docFromHandle = handle._doc {
                    // We have the document - so being in loading means "try to save this to
                    // a storage provider, if one exists", then hand it back as good.
                    Task.detached {
                        try await self.storage?.saveDoc(id: id, doc: docFromHandle)
                    }
                    // TODO: if we're allowed and prolific in gossip, notify any connected
                    // peers there's a new document before jumping to the 'ready' state
                    handle.state = .ready
                    handles[id] = handle
                    return docFromHandle
                } else {
                    // We don't have the underlying Automerge document, so attempt
                    // to load it from storage, and failing that - if the storage provider
                    // doesn't exist, for example - jump forward to attempting to fetch
                    // it from a peer.
                    if let doc = try await loadFromStorage(id: id) {
                        handle.state = .ready
                        handles[id] = handle
                        return doc
                    } else {
                        handle.state = .requesting
                        handles[id] = handle
                        return try await resolveDocHandle(id: id)
                    }
                }
            case .requesting:
                assert(handle._doc == nil)
                if let docFromNetwork = try await self.network.remoteFetch(id: handle.id) {
                    handle._doc = docFromNetwork
                    Task.detached {
                        try await self.storage?.saveDoc(id: id, doc: docFromNetwork)
                    }
                    handle.state = .ready
                    handles[id] = handle
                    return docFromNetwork
                } else {
                    handle.state = .unavailable
                    handles[handle.id] = handle
                    throw Errors.DocUnavailable(id: handle.id)
                }
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

    private func loadFromStorage(id: DocumentId) async throws -> Document? {
        guard let storage = self.storage else {
            return nil
        }
        return try await storage.loadDoc(id: id)
    }

    private func purgeFromStorage(id: DocumentId) async throws {
        guard let storage = self.storage else {
            return
        }
        try await storage.purgeDoc(id: id)
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
