//
//  WebSocketMessages.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 1/24/24.
//

import Foundation

// related source for the automerge-repo sync code:
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo-network-websocket/src/BrowserWebSocketClientAdapter.ts
// It looks like all websocket messages are CBOR encoded as data streams
//
// 1. So first step is getting through the handshake, then we can find and sort
// the sync messages that flow back and forth.

// CDDL pre-amble
// ; The base64 encoded bytes of a Peer ID
// peer_id = str
// ; The possible protocol versions (currently always the string "1")
// protocol_version = "1"
// ; The bytes of an automerge sync message
// sync_message = bstr
// ; The base58check encoded bytes of a document ID
// document_id = str
//
// - join -
// {
//    type: "join",
//    senderId: peer_id,
//    supportedProtocolVersions: protocol_version
// }

struct JoinMsg: Codable {
    var type: String = "join"
    let senderId: String
    var supportedProtocolVersions: String = "1"

    init(senderId: String) {
        self.senderId = senderId
    }
}

// - peer - (expected response to join)
// {
//    type: "peer",
//    senderId: peer_id,
//    selectedProtocolVersion: protocol_version,
//    targetId: peer_id,
// }

// {
//   "type": "peer",
//   "senderId": "storage-server-sync-automerge-org",
//   "peerMetadata": {"storageId": "3760df37-a4c6-4f66-9ecd-732039a9385d", "isEphemeral": false},
//   "selectedProtocolVersion": "1",
//   "targetId": "FA38A1B2-1433-49E7-8C3C-5F63C117DF09"
// }

struct PeerMsg: Codable {
    var type: String = "peer"
    let senderId: String
    let targetId: String
    var selectedProtocolVersion: String

    init(senderId: String, targetId: String) {
        self.senderId = senderId
        self.targetId = targetId
        self.selectedProtocolVersion = "1"
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
