//
//  WebSocketMessages.swift
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

/// A type that represents a peer
///
/// Typically a UUID4 in string form.
typealias PEER_ID = String

/// A type that represents an identity for the storage of a peer.
///
/// Typically a UUID4 in string form. Receiving peers may tie cached sync state for documents to this identifier.
typealias STORAGE_ID = String

/// A type that represents a document Id.
///
/// Typically 16 bytes encoded in bs58 format.
typealias DOCUMENT_ID = String

/// A type that represents the raw bytes of an Automerge sync message.
typealias SYNC_MESSAGE = Data

// ; Metadata sent in either the join or peer message types
// peer_metadata = {
//    ; The storage ID of this peer
//    ? storageId: storage_id,
//    ; Whether the sender expects to connect again with this storage ID
//    isEphemeral: bool
// }

/// A type that encapsulates valid V1 protocol messages for the Automerge-repo sync protocol.
indirect enum V1Msg {
    static let encoder = CBOREncoder()
    static let decoder = CBORDecoder()

    case peer(PeerMsg)
    case join(JoinMsg)
    case error(ErrorMsg)
    case request(RequestMsg)
    case sync(SyncMsg)
    case unavailable(UnavailableMsg)
    // ephemeral
    case ephemeral(EphemeralMsg)
    // gossip additions
    case remoteSubscriptionChange(RemoteSubscriptionChangeMsg)
    case remoteheadschanged(RemoteHeadsChangedMsg)
    // fall-through scenario - unknown message
    case unknown(Data)

    /// Attempts to decode the data you provide as a peer message.
    ///
    /// - Parameter data: The data to decode
    /// - Returns: The decoded message, or ``V1Msg/unknown(_:)`` if the decoding attempt failed.
    static func decodePeer(_ data: Data) -> V1Msg {
        if let peerMsg = attemptPeer(data) {
            return .peer(peerMsg)
        } else {
            return .unknown(data)
        }
    }

    /// Exhaustively attempt to decode incoming data as V1 protocol messages.
    ///
    /// - Parameters:
    ///   - data: The data to decode.
    ///   - withGossip: A Boolean value that indicates whether to include decoding of handshake messages.
    ///   - withHandshake: A Boolean value that indicates whether to include decoding of gossip messages.
    /// - Returns: The decoded message, or ``V1Msg/unknown(_:)`` if the previous decoding attempts failed.
    ///
    /// The decoding is ordered from the perspective of an initiating client expecting a response to minimize attempts.
    /// Enable `withGossip` to attempt to decode head gossip messages, and `withHandshake` to include handshake phase
    /// messages.
    /// With both `withGossip` and `withHandshake` set to `true`, the decoding is exhaustive over all V1 messages.
    static func decode(_ data: Data, withGossip: Bool = false, withHandshake: Bool = false) -> V1Msg {
        if withHandshake {
            if let peerMsg = attemptPeer(data) {
                return .peer(peerMsg)
            }
        }

        if withGossip {
            if let remoteHeadsChanged = attemptRemoteHeadsChanged(data) {
                return .remoteheadschanged(remoteHeadsChanged)
            }
        }

        if let syncMsg = attemptSync(data) {
            return .sync(syncMsg)
        }

        if let ephemeralMsg = attemptEphemeral(data) {
            return .ephemeral(ephemeralMsg)
        }

        if let errorMsg = attemptError(data) {
            return .error(errorMsg)
        }

        if let unavailableMsg = attemptUnavailable(data) {
            return .unavailable(unavailableMsg)
        }

        // exhaustive - probably unexpected messages from an initiating client

        if withHandshake {
            if let joinMsg = attemptJoin(data) {
                return .join(joinMsg)
            }
        }

        if withGossip {
            if let remoteSubChangeMsg = attemptRemoteSubscriptionChange(data) {
                return .remoteSubscriptionChange(remoteSubChangeMsg)
            }
        }

        if let requestMsg = attemptRequest(data) {
            return .request(requestMsg)
        }

        return .unknown(data)
    }

    // sync phase messages

    static func attemptSync(_ data: Data) -> SyncMsg? {
        do {
            return try decoder.decode(SyncMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as SyncMsg")
        }
        return nil
    }

    static func attemptRequest(_ data: Data) -> RequestMsg? {
        do {
            return try decoder.decode(RequestMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as RequestMsg")
        }
        return nil
    }

    static func attemptUnavailable(_ data: Data) -> UnavailableMsg? {
        do {
            return try decoder.decode(UnavailableMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as UnavailableMsg")
        }
        return nil
    }

    // handshake phase messages

    static func attemptPeer(_ data: Data) -> PeerMsg? {
        do {
            return try decoder.decode(PeerMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as PeerMsg")
        }
        return nil
    }

    static func attemptJoin(_ data: Data) -> JoinMsg? {
        do {
            return try decoder.decode(JoinMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as JoinMsg")
        }
        return nil
    }

    // error

    static func attemptError(_ data: Data) -> ErrorMsg? {
        do {
            return try decoder.decode(ErrorMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as ErrorMsg")
        }
        return nil
    }

    // ephemeral

    static func attemptEphemeral(_ data: Data) -> EphemeralMsg? {
        do {
            return try decoder.decode(EphemeralMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as EphemeralMsg")
        }
        return nil
    }

    // gossip

    static func attemptRemoteHeadsChanged(_ data: Data) -> RemoteHeadsChangedMsg? {
        do {
            return try decoder.decode(RemoteHeadsChangedMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as RemoteHeadsChangedMsg")
        }
        return nil
    }

    static func attemptRemoteSubscriptionChange(_ data: Data) -> RemoteSubscriptionChangeMsg? {
        do {
            return try decoder.decode(RemoteSubscriptionChangeMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as RemoteSubscriptionChangeMsg")
        }
        return nil
    }

    // encode messages

    static func encode(_ msg: JoinMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: RequestMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: SyncMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: PeerMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: UnavailableMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: EphemeralMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: RemoteSubscriptionChangeMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: RemoteHeadsChangedMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: ErrorMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: V1Msg) throws -> Data {
        // not sure this is useful, but might as well finish out the set...
        switch msg {
        case let .peer(peerMsg):
            return try encode(peerMsg)
        case let .join(joinMsg):
            return try encode(joinMsg)
        case let .error(errorMsg):
            return try encode(errorMsg)
        case let .request(requestMsg):
            return try encode(requestMsg)
        case let .sync(syncMsg):
            return try encode(syncMsg)
        case let .unavailable(unavailableMsg):
            return try encode(unavailableMsg)
        case let .ephemeral(ephemeralMsg):
            return try encode(ephemeralMsg)
        case let .remoteSubscriptionChange(remoteSubscriptionChangeMsg):
            return try encode(remoteSubscriptionChangeMsg)
        case let .remoteheadschanged(remoteHeadsChangedMsg):
            return try encode(remoteHeadsChangedMsg)
        case let .unknown(data):
            return data
        }
    }
}

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

/// A message that indicates a desire to peer and sync documents.
///
/// Sent by the initiating peer (represented by `senderId`) to initiate a connection to manage documents between peers.
/// The next response is expected to be a ``PeerMsg``. If any other message is received after sending `JoinMsg`, the
/// initiating client should disconnect.
/// If the receiving peer receives any message other than a `JoinMsg` from the initiating peer, it is expected to
/// terminate the connection.
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

/// A message that acknowledges a join request.
///
/// A response sent by a receiving peer (represented by `targetId`) after receiving a ``JoinMsg`` that indicates sync,
/// gossiping, and ephemeral messages may now be initiated.
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

/// A sync error message
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

/// A request to synchronize an Automerge document.
///
/// Sent when the initiating peer (represented by `senderId`) is asking to begin sync for the given document ID.
/// Identical to ``SyncMsg`` but indicates to the receiving peer that the sender would like an ``UnavailableMsg``
/// message if the receiving peer (represented by `targetId` does not have the document (identified by `documentId`).
struct RequestMsg: Codable {
    var type: String = "request"
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

/// A request to synchronize an Automerge document.
///
/// Sent when the initiating peer (represented by `senderId`) is asking to begin sync for the given document ID.
/// Use `SyncMsg` instead of `RequestMsg` when you are creating a new Automerge document that you want to share.
///
/// If the receiving peer doesn't have an Automerge document represented by `documentId` and can't or won't store the
/// document.
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

/// A message that indicates a document is unavailable.
///
/// Generally a response for a ``RequestMsg`` from an initiating peer (represented by `senderId`) that the receiving
/// peer (represented by `targetId`) doesn't have a copy of the requested Document, or is unable to share it.
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

struct RemoteSubscriptionChangeMsg: Codable {
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

struct RemoteHeadsChangedMsg: Codable {
    struct HeadsAtTime: Codable {
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
