//
//  WebSocketMessages.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 1/24/24.
//

import Foundation

// related source for the automerge-repo sync code:
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo-network-websocket/src/BrowserWebSocketClientAdapter.ts
// All the websocket messages are CBOR encoded and sent as data streams

// CDDL pre-amble
// ; The base64 encoded bytes of a Peer ID
// peer_id = str
// ; The base64 encoded bytes of a Storage ID
// storage_id = str
// ; The possible protocol versions (currently always the string "1")
// protocol_version = "1"
// ; The bytes of an automerge sync message
// sync_message = bstr
// ; The base58check encoded bytes of a document ID
// document_id = str

typealias PEER_ID = String
typealias STORAGE_ID = String
typealias DOCUMENT_ID = String
typealias SYNC_MESSAGE = Data

// ; Metadata sent in either the join or peer message types
// peer_metadata = {
//    ; The storage ID of this peer
//    ? storageId: storage_id,
//    ; Whether the sender expects to connect again with this storage ID
//    isEphemeral: bool
// }

struct PeerMetadata: Codable {
    var storageId: STORAGE_ID?
    var isEphemeral: Bool

    init(storageId: STORAGE_ID? = nil, isEphemeral: Bool) {
        self.storageId = storageId
        self.isEphemeral = isEphemeral
    }
}

// - join -
// {
//    type: "join",
//    senderId: peer_id,
//    supportedProtocolVersions: protocol_version
//    ? metadata: peer_metadata,
// }

// MARK: Join/Peer

struct JoinMsg: Codable {
    var type: String = "join"
    let senderId: PEER_ID
    var supportedProtocolVersions: String = "1"
    var peerMetadata: PeerMetadata?

    init(senderId: PEER_ID, metadata: PeerMetadata? = nil) {
        self.senderId = senderId
        if let metadata {
            self.peerMetadata = metadata
        }
    }
}

// - peer - (expected response to join)
// {
//    type: "peer",
//    senderId: peer_id,
//    selectedProtocolVersion: protocol_version,
//    targetId: peer_id,
//    ? metadata: peer_metadata,
// }

// example output from sync.automerge.org:
// {
//   "type": "peer",
//   "senderId": "storage-server-sync-automerge-org",
//   "peerMetadata": {"storageId": "3760df37-a4c6-4f66-9ecd-732039a9385d", "isEphemeral": false},
//   "selectedProtocolVersion": "1",
//   "targetId": "FA38A1B2-1433-49E7-8C3C-5F63C117DF09"
// }

struct PeerMsg: Codable {
    var type: String = "peer"
    let senderId: PEER_ID
    let targetId: PEER_ID
    var peerMetadata: PeerMetadata?
    var selectedProtocolVersion: String

    init(senderId: PEER_ID, targetId: PEER_ID, storageId: String?, ephemeral: Bool = true) {
        self.senderId = senderId
        self.targetId = targetId
        self.selectedProtocolVersion = "1"
        self.peerMetadata = PeerMetadata(storageId: storageId, isEphemeral: ephemeral)
    }
}

// - error -
// {
//    type: "error",
//    message: str,
// }

struct ErrorMsg: Codable {
    var type: String = "error"
    let message: String

    init(message: String) {
        self.message = message
    }
}

// MARK: Sync

// - request -
// {
//    type: "request",
//    documentId: document_id,
//    ; The peer requesting to begin sync
//    senderId: peer_id,
//    targetId: peer_id,
//    ; The initial automerge sync message from the sender
//    data: sync_message
// }

struct RequestMsg: Codable {
    var type: String = "error"
    let documentId: DOCUMENT_ID
    let senderId: PEER_ID // The peer requesting to begin sync
    let targetId: PEER_ID
    let sync_message: Data // The initial automerge sync message from the sender

    init(documentId: DOCUMENT_ID, senderId: PEER_ID, targetId: PEER_ID, sync_message: Data) {
        self.documentId = documentId
        self.senderId = senderId
        self.targetId = targetId
        self.sync_message = sync_message
    }
}

// - sync -
// {
//    type: "sync",
//    documentId: document_id,
//    ; The peer requesting to begin sync
//    senderId: peer_id,
//    targetId: peer_id,
//    ; The initial automerge sync message from the sender
//    data: sync_message
// }

struct SyncMsg: Codable {
    var type = "sync"
    let documentId: DOCUMENT_ID
    let senderId: PEER_ID // The peer requesting to begin sync
    let targetId: PEER_ID
    let data: Data // The initial automerge sync message from the sender

    init(documentId: DOCUMENT_ID, senderId: PEER_ID, targetId: PEER_ID, data: Data) {
        self.documentId = documentId
        self.senderId = senderId
        self.targetId = targetId
        self.data = data
    }
}

// - unavailable -
// {
//  type: "doc-unavailable",
//  senderId: peer_id,
//  targetId: peer_id,
//  documentId: document_id,
// }

struct UnavailableMsg: Codable {
    var type = "doc-unavailable"
    let documentId: DOCUMENT_ID
    let senderId: PEER_ID
    let targetId: PEER_ID

    init(documentId: DOCUMENT_ID, senderId: PEER_ID, targetId: PEER_ID) {
        self.documentId = documentId
        self.senderId = senderId
        self.targetId = targetId
    }
}

// MARK: Ephemeral

// - ephemeral -
// {
//  type: "ephemeral",
//  ; The peer who sent this message
//  senderId: peer_id,
//  ; The target of this message
//  targetId: peer_id,
//  ; The sequence number of this message within its session
//  count: uint,
//  ; The unique session identifying this stream of ephemeral messages
//  sessionId: str,
//  ; The document ID this ephemera relates to
//  documentId: document_id,
//  ; The data of this message (in practice this is arbitrary CBOR)
//  data: bstr
// }

struct EphemeralMsg: Codable {
    var type = "ephemeral"
    let senderId: PEER_ID
    let targetId: PEER_ID
    let count: UInt
    let sessionId: String
    let documentId: DOCUMENT_ID
    let data: Data

    init(senderId: PEER_ID, targetId: PEER_ID, count: UInt, sessionId: String, documentId: DOCUMENT_ID, data: Data) {
        self.senderId = senderId
        self.targetId = targetId
        self.count = count
        self.sessionId = sessionId
        self.documentId = documentId
        self.data = data
    }
}

// MARK: Head's Gossiping

// - remote subscription changed -
// {
//  type: "remote-subscription-change"
//  senderId: peer_id
//  targetId: peer_id
//
//  ; The storage IDs to add to the subscription
//  ? add: [* storage_id]
//
//  ; The storage IDs to remove from the subscription
//  remove: [* storage_id]
// }

struct RemoteSubscriptionChangedMsg {
    var type = "remote-subscription-change"
    let senderId: PEER_ID
    let targetId: PEER_ID
    var add: [STORAGE_ID]?
    var remove: [STORAGE_ID]

    init(senderId: PEER_ID, targetId: PEER_ID, add: [STORAGE_ID]? = nil, remove: [STORAGE_ID]) {
        self.senderId = senderId
        self.targetId = targetId
        self.add = add
        self.remove = remove
    }
}

// - remote heads changed
// {
//  type: "remote-heads-changed"
//  senderId: peer_id
//  targetId: peer_id
//
//  ; The document ID of the document that has changed
//  documentId: document_id
//
//  ; A map from storage ID to the heads advertised for a given storage ID
//  newHeads: {
//    * storage_id => {
//      ; The heads of the new document for the given storage ID as
//      ; a list of base64 encoded SHA2 hashes
//      heads: [* string]
//      ; The local time on the node which initially sent the remote-heads-changed
//      ; message as milliseconds since the unix epoch
//      timestamp: uint
//    }
//  }
// }

struct RemoteHeadsChangedMsg {
    struct HeadsAtTime {
        var heads: [String]
        let timestamp: uint

        init(heads: [String], timestamp: uint) {
            self.heads = heads
            self.timestamp = timestamp
        }
    }

    var type = "remote-heads-changed"
    let senderId: PEER_ID
    let targetId: PEER_ID
    let documentId: DOCUMENT_ID
    var newHeads: [STORAGE_ID: HeadsAtTime]
    var add: [STORAGE_ID]
    var remove: [STORAGE_ID]

    init(
        senderId: PEER_ID,
        targetId: PEER_ID,
        documentId: DOCUMENT_ID,
        newHeads: [STORAGE_ID: HeadsAtTime],
        add: [STORAGE_ID],
        remove: [STORAGE_ID]
    ) {
        self.senderId = senderId
        self.targetId = targetId
        self.documentId = documentId
        self.newHeads = newHeads
        self.add = add
        self.remove = remove
    }
}
