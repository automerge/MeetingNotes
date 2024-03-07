//
//  SyncV1.swift
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
public indirect enum SyncV1 {
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

    /// A type that represents a peer
    ///
    /// Typically a UUID4 in string form.
    public typealias PEER_ID = String

    /// A type that represents an identity for the storage of a peer.
    ///
    /// Typically a UUID4 in string form. Receiving peers may tie cached sync state for documents to this identifier.
    public typealias STORAGE_ID = String

    /// A type that represents a document Id.
    ///
    /// Typically 16 bytes encoded in bs58 format.
    public typealias DOCUMENT_ID = String

    /// A type that represents the raw bytes of an Automerge sync message.
    public typealias SYNC_MESSAGE = Data

    static let encoder = CBOREncoder()
    static let decoder = CBORDecoder()

    /// The collection of value "type" strings for the V1 automerge-repo protocol.
    public enum MsgTypes {
        static var peer = "peer"
        static var join = "join"
        static var leave = "leave"
        static var request = "request"
        static var sync = "sync"
        static var ephemeral = "ephemeral"
        static var error = "error"
        static var unavailable = "doc-unavailable"
        static var remoteHeadsChanged = "remote-heads-changed"
        static var remoteSubscriptionChange = "remote-subscription-change"
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

extension SyncV1: CustomDebugStringConvertible {
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
