//
//  SyncV1Msg.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 1/24/24.
//

import Foundation
import OSLog
import PotentCBOR

// Automerge Repo WebSocket sync details:
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo-network-websocket/README.md
// explicitly using a protocol version "1" here - make sure to specify (and verify?) that

// related source for the automerge-repo sync code:
// https://github.com/automerge/automerge-repo/blob/main/packages/automerge-repo-network-websocket/src/BrowserWebSocketClientAdapter.ts
// All the WebSocket messages are CBOR encoded and sent as data streams

/// A type that encapsulates valid V1 Automerge-repo sync protocol messages.
public indirect enum SyncV1Msg: Sendable {
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

    /// The collection of value "type" strings for the V1 automerge-repo protocol.
    public enum MsgTypes: Sendable {
        public static let peer = "peer"
        public static let join = "join"
        public static let leave = "leave"
        public static let request = "request"
        public static let sync = "sync"
        public static let ephemeral = "ephemeral"
        public static let error = "error"
        public static let unavailable = "doc-unavailable"
        public static let remoteHeadsChanged = "remote-heads-changed"
        public static let remoteSubscriptionChange = "remote-subscription-change"
    }

    case peer(PeerMsg)
    case join(JoinMsg)
    case leave(LeaveMsg)
    case error(ErrorMsg)
    case request(RequestMsg)
    case sync(SyncMsg)
    case unavailable(UnavailableMsg)
    // ephemeral
    case ephemeral(EphemeralMsg)
    // gossip additions
    case remoteSubscriptionChange(RemoteSubscriptionChangeMsg)
    case remoteHeadsChanged(RemoteHeadsChangedMsg)
    // fall-through scenario - unknown message
    case unknown(Data)

    var peerMessageType: P2PSyncMessageType {
        switch self {
        case .peer:
            P2PSyncMessageType.peer
        case .join:
            P2PSyncMessageType.join
        case .leave:
            P2PSyncMessageType.leave
        case .error:
            P2PSyncMessageType.syncerror
        case .request:
            P2PSyncMessageType.request
        case .sync:
            P2PSyncMessageType.sync
        case .unavailable:
            P2PSyncMessageType.unavailable
        case .ephemeral:
            P2PSyncMessageType.ephemeral
        case .remoteSubscriptionChange:
            P2PSyncMessageType.remoteSubscriptionChange
        case .remoteHeadsChanged:
            P2PSyncMessageType.remoteHeadsChanged
        case .unknown:
            P2PSyncMessageType.unknown
        }
    }
}

extension SyncV1Msg: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .peer(interior_msg):
            interior_msg.debugDescription
        case let .join(interior_msg):
            interior_msg.debugDescription
        case let .leave(interior_msg):
            interior_msg.debugDescription
        case let .error(interior_msg):
            interior_msg.debugDescription
        case let .request(interior_msg):
            interior_msg.debugDescription
        case let .sync(interior_msg):
            interior_msg.debugDescription
        case let .unavailable(interior_msg):
            interior_msg.debugDescription
        case let .ephemeral(interior_msg):
            interior_msg.debugDescription
        case let .remoteSubscriptionChange(interior_msg):
            interior_msg.debugDescription
        case let .remoteHeadsChanged(interior_msg):
            interior_msg.debugDescription
        case let .unknown(data):
            "UNKNOWN[data: \(data.hexEncodedString(uppercase: false))]"
        }
    }
}
