

import Automerge
import Foundation

public actor Repo {
    // to replace DocumentSyncCoordinator
    private var _handles: [DocumentId: DocHandle]
    private var storage: StorageProvider?
    private var network: NetworkSubsystem

    init(storage: StorageProvider? = nil, networkAdapters: [any NetworkProvider] = []) {
        self._handles = [:]
        self.storage = storage
        self.network = NetworkSubsystem(adapters: networkAdapters)
    }

    public func handles() async -> [DocHandle] {
        []
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

    public func clone(id: DocumentId) async -> DocHandle {
        DocHandle(id: DocumentId(), isNew: false)
    }

    public func find(id: DocumentId) async throws -> DocHandle {
        DocHandle(id: id, isNew: false)
        // TODO: attempt to load, failing that, req from network
    }

    public func delete(id _: DocumentId) async {}

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
