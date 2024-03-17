import struct Automerge.ChangeHash
import class Automerge.Document
import struct Automerge.SyncState
import struct Foundation.Data

// actor?
// class?
// Object intention is ONLY data storage, used by (and protected underneath) Repo - so leaning
// towards `struct` at the moment, with the relevant states being updated by it's owner (Repo)
// since this object doesn't know about storage (if it exists) or network and relevant network
// peers to request

// ... damnit - it's the type that's exposed to users to provide a proxy for an Automerge Document,
// so maybe it _should_ be an actor
struct DocHandle: Sendable {
    enum DocHandleState {
        case idle
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

    let id: DocumentId
    weak var _doc: Automerge.Document?
    var state: DocHandleState
    var remoteHeads: [STORAGE_ID: Set<Automerge.ChangeHash>]
    var syncStates: [PEER_ID: SyncState]

    // TODO: verify that we want a timeout delay per Document, as opposed to per-Repo
    var timeoutDelay: Double

    init(id: DocumentId, isNew: Bool, initialValue: Automerge.Document? = nil, timeoutDelay: Double = 1.0) {
        self.id = id
        self.timeoutDelay = timeoutDelay
        remoteHeads = [:]
        syncStates = [:]
        // isNew is when we're creating content and it needs to get stored locally in a storage
        // provider, if available.
        if isNew {
            self.state = .loading
        } else {
            self.state = .ready
            self._doc = initialValue ?? Document()
        }
    }

    var isReady: Bool {
        self.state == .ready
    }

    var isDeleted: Bool {
        self.state == .deleted
    }

    var isUnavailable: Bool {
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
}
