import class Combine.PassthroughSubject
import struct Foundation.Data

// riff
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo/src/network/NetworkSubsystem.ts

/// A type that hosts network subsystems to connect to peers.
///
/// The NetworkSubsystem instance is responsible for setting up and configuring any network providers, and responding to
/// messages from remote peers after the connection has been established. The connection handshake and peer negotiation
/// is
/// the responsibility of the network provider instance.
public struct NetworkSubsystem {
    var adapters: [any NetworkProvider]

    init(adapters: [any NetworkProvider]) {
        self.adapters = adapters
    }

    func send(message _: Data) {}

    // async waits until underlying networks are connected and ready to send and receive messages
    // (aka all networks are connected and "peered")
    func isReady() async -> Bool {
        false
    }

    func whenReady() async {}

    let eventPublisher: PassthroughSubject<NetworkAdapterEvents, Never> = PassthroughSubject()
}

// struggling with "what's the point" of this type - seems to be only to verify that all
// network connections are ready.
//
// doesn't appear to hold or manage any state, just act as a pass through based on this interface
// in the upstream inspiration, it divides up the network messages from below to break out messages
// intended to sync or update a repository, and messages (ephemeral) that should be forwarded out
// to the application.
//
// it also appears to update information on an ephemeral information (a sort of middleware) before
// emitting it upwards.
// Expected message types to forward:
//    isSyncMessage(message) ||
//    isEphemeralMessage(message) ||
//    isRequestMessage(message) ||
//    isDocumentUnavailableMessage(message) ||
//    isRemoteSubscriptionControlMessage(message) ||
//    isRemoteHeadsChanged(message)
//
// It feels like maybe NetworkSubsystem is where I _should_ host NWBrowser and NWListener
// (and any configuration options for the same). In my initial implementation, I looked for any
// like-minded peers and attempted to sync content with them (auto-connect) and then maintain
// changes as they flowed. The default/built-in interface to Automerge-repo doesn't accommodate
// the browsing/showing possible peers aspect, and what that might look like, but I could 1) emit
// more events with details of available peers to connect to and 2) auto-connect and try my best

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

// DocHandle
/** DocHandle is a wrapper around a single Automerge document that lets us
 * listen for changes and notify the network and storage of new changes.
 *
 * @remarks
 * A `DocHandle` represents a document which is being managed by a {@link Repo}.
 * To obtain `DocHandle` use {@link Repo.find} or {@link Repo.create}.
 *
 * To modify the underlying document use either {@link DocHandle.change} or
 * {@link DocHandle.changeAt}. These methods will notify the `Repo` that some
 * change has occured and the `Repo` will save any new changes to the
 * attached {@link StorageAdapter} and send sync messages to connected peers.
 * */
//  property: documentId: DocumentId
//  property: url: AutomergeURL (maybe ignore this...)
// - func broadcast(msg) - sends ephemeral message to all connected peers
// - func change?? (callback called when changes happen?) - provide a closure that's called, passing in an Automerge
// document to make any relevant updates, and ultimately returns a set of heads that represents the change having been
// made.
// - func changeAt?? (callback called when changes happen?) - makes a change as if the document were at <heads>
// - func delete() -> Void
// - func doc() async -> Automerge.Document
// - func getRemoteHeads(storageId) -> [ChangeHash]
// - func isDeleted() -> Bool
// - func isReady() -> Bool
// - func isUnavailable() -> Bool
// - func merge(DocHandle) -> Void
//  - loosely a convenience over handle.change(doc => A.merge(doc, otherHandle.docSync()))

// SharePolicy
// func(peerId, documentId) -> Bool  - do we share this document with this peer?
