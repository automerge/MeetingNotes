import struct Automerge.ChangeHash
import class Automerge.Document
import struct Foundation.Data

// actor?
// class?
// Object intention is ONLY data storage, used by (and protected underneath) Repo - so leaning
// towards `struct` at the moment, with the relevant states being updated by it's owner (Repo)
// since this object doesn't know about storage (if it exists) or network and relevant network
// peers to request

// ... damnit - it's the type that's exposed to users to provide a proxy for an Automerge Document,
// so maybe it _should_ be an actor
public struct DocHandle {
    enum DocHandleState {
        case new
        case loading
        case requesting
        case ready
        case unavailable
        case deleted
    }

    // NOTE: heckj - what I was originally researching how this all goes together, I
    // wondered if there wasn't the concept of unloading/reloading the bytes from memory and
    // onto disk when there was a storage system available - in that case, we'd need a few
    // more states to this diagram (originally from `automerge-repo`) - one for 'purged' and
    // an associated action PURGE - the idea being that might be invoked when an app is coming
    // under memory pressure.

    /**
     * Internally we use a state machine to orchestrate document loading and/or syncing, in order to
     * avoid requesting data we already have, or surfacing intermediate values to the consumer.
     *
     *                          ┌─────────────────────┬─────────TIMEOUT────►┌─────────────┐
     *                      ┌───┴─────┐           ┌───┴────────┐            │ unavailable │
     *  ┌───────┐  ┌──FIND──┤ loading ├─REQUEST──►│ requesting ├─UPDATE──┐  └─────────────┘
     *  │ idle  ├──┤        └───┬─────┘           └────────────┘         │
     *  └───────┘  │            │                                        └─►┌────────┐
     *             │            └───────LOAD───────────────────────────────►│ ready  │
     *             └──CREATE───────────────────────────────────────────────►└────────┘
     */

    weak var value: Automerge.Document?
    var state: DocHandleState
    public let id: DocumentId
    var remoteHeads: [STORAGE_ID: Set<Automerge.ChangeHash>]

    init(id: DocumentId, isNew _: Bool, initialValue: Automerge.Document? = nil, timeoutDelay _: Double = 1.0) {
        self.state = .new
        self.id = id
        remoteHeads = [:]
        self.value = initialValue
    }

    public var doc: Document? {
        guard self.state == .ready else {
            return nil
        }
        return self.value
    }

    public var isReady: Bool {
        self.state == .ready
    }

    public var isDeleted: Bool {
        self.state == .deleted
    }

    public var isUnavailable: Bool {
        self.state == .unavailable
    }

    // not entirely sure why this is holding data about remote heads... convenience?
    // why not track within Repo?
    func getRemoteHeads(id: STORAGE_ID) async -> Set<ChangeHash>? {
        remoteHeads[id]
    }

    mutating func setRemoteHeads(id: STORAGE_ID, heads: Set<ChangeHash>) {
        remoteHeads[id] = heads
    }

    func merge(other _: DocHandle) async {}
}

// ?? Rename this to DocHandle - it doesn't do the same thing that Automerge-repo's DocHandle does
// though...

// - init(id: DocumentId, isNew: Bool, initialValue:Doc/[u8], timeoutDelay:seconds)
//    - prop [StorageId: Heads]
//
// - isReady()
// - isDeleted()
// - isUnavailable()
// - var doc async { AutomergeDoc}
// - setRemoteHeads(StorageId, Heads)
// - getRemoteHeads(StorageId)
// - change
// - changeAt
// - merge(AnotherDocHandle)

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
