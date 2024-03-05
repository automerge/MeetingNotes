import Foundation

public extension SyncV1 {
    // ; Metadata sent in either the join or peer message types
    // peer_metadata = {
    //    ; The storage ID of this peer
    //    ? storageId: storage_id,
    //    ; Whether the sender expects to connect again with this storage ID
    //    isEphemeral: bool
    // }

    struct PeerMetadata: Codable, CustomDebugStringConvertible {
        public var storageId: STORAGE_ID?
        public var isEphemeral: Bool

        public init(storageId: STORAGE_ID? = nil, isEphemeral: Bool) {
            self.storageId = storageId
            self.isEphemeral = isEphemeral
        }

        public var debugDescription: String {
            "[storageId: \(storageId ?? "nil"), ephemeral: \(isEphemeral)]"
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
    /// Sent by the initiating peer (represented by `senderId`) to initiate a connection to manage documents between
    /// peers.
    /// The next response is expected to be a ``PeerMsg``. If any other message is received after sending `JoinMsg`, the
    /// initiating client should disconnect.
    /// If the receiving peer receives any message other than a `JoinMsg` from the initiating peer, it is expected to
    /// terminate the connection.
    struct JoinMsg: Codable, CustomDebugStringConvertible {
        public var type: String = SyncV1.MsgTypes.join
        public let senderId: PEER_ID
        public var supportedProtocolVersions: String = "1"
        public var peerMetadata: PeerMetadata?

        public init(senderId: PEER_ID, metadata: PeerMetadata? = nil) {
            self.senderId = senderId
            if let metadata {
                self.peerMetadata = metadata
            }
        }

        public var debugDescription: String {
            "JOIN[version: \(supportedProtocolVersions), sender: \(senderId), metadata: \(peerMetadata?.debugDescription ?? "nil")]"
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
    /// A response sent by a receiving peer (represented by `targetId`) after receiving a ``JoinMsg`` that indicates
    /// sync,
    /// gossiping, and ephemeral messages may now be initiated.
    struct PeerMsg: Codable, CustomDebugStringConvertible {
        public var type: String = SyncV1.MsgTypes.peer
        public let senderId: PEER_ID
        public let targetId: PEER_ID
        public var peerMetadata: PeerMetadata?
        public var selectedProtocolVersion: String

        public init(senderId: PEER_ID, targetId: PEER_ID, storageId: String?, ephemeral: Bool = true) {
            self.senderId = senderId
            self.targetId = targetId
            self.selectedProtocolVersion = "1"
            self.peerMetadata = PeerMetadata(storageId: storageId, isEphemeral: ephemeral)
        }

        public var debugDescription: String {
            "PEER[version: \(selectedProtocolVersion), sender: \(senderId), target: \(targetId), metadata: \(peerMetadata?.debugDescription ?? "nil")]"
        }
    }

    // - error -
    // {
    //    type: "error",
    //    message: str,
    // }

    /// A sync error message
    struct ErrorMsg: Codable, CustomDebugStringConvertible {
        public var type: String = SyncV1.MsgTypes.error
        public let message: String

        public init(message: String) {
            self.message = message
        }

        public var debugDescription: String {
            "ERROR[msg: \(message)"
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
    /// message if the receiving peer (represented by `targetId` does not have the document (identified by
    /// `documentId`).
    struct RequestMsg: Codable, CustomDebugStringConvertible {
        public var type: String = SyncV1.MsgTypes.request
        public let documentId: DOCUMENT_ID
        public let senderId: PEER_ID // The peer requesting to begin sync
        public let targetId: PEER_ID
        public let data: Data // The initial automerge sync message from the sender

        public init(documentId: DOCUMENT_ID, senderId: PEER_ID, targetId: PEER_ID, sync_message: Data) {
            self.documentId = documentId
            self.senderId = senderId
            self.targetId = targetId
            self.data = sync_message
        }

        public var debugDescription: String {
            "REQUEST[documentId: \(documentId), sender: \(senderId), target: \(targetId), data: \(data.count) bytes]"
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
    /// If the receiving peer doesn't have an Automerge document represented by `documentId` and can't or won't store
    /// the
    /// document.
    struct SyncMsg: Codable, CustomDebugStringConvertible {
        public var type = SyncV1.MsgTypes.sync
        public let documentId: DOCUMENT_ID
        public let senderId: PEER_ID // The peer requesting to begin sync
        public let targetId: PEER_ID
        public let data: Data // The initial automerge sync message from the sender

        public init(documentId: DOCUMENT_ID, senderId: PEER_ID, targetId: PEER_ID, sync_message: Data) {
            self.documentId = documentId
            self.senderId = senderId
            self.targetId = targetId
            self.data = sync_message
        }

        public var debugDescription: String {
            "SYNC[documentId: \(documentId), sender: \(senderId), target: \(targetId), data: \(data.count) bytes]"
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
    struct UnavailableMsg: Codable, CustomDebugStringConvertible {
        public var type = SyncV1.MsgTypes.unavailable
        public let documentId: DOCUMENT_ID
        public let senderId: PEER_ID
        public let targetId: PEER_ID

        public init(documentId: DOCUMENT_ID, senderId: PEER_ID, targetId: PEER_ID) {
            self.documentId = documentId
            self.senderId = senderId
            self.targetId = targetId
        }

        public var debugDescription: String {
            "UNAVAILABLE[documentId: \(documentId), sender: \(senderId), target: \(targetId)]"
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

    struct EphemeralMsg: Codable, CustomDebugStringConvertible {
        public var type = SyncV1.MsgTypes.ephemeral
        public let senderId: PEER_ID
        public let targetId: PEER_ID
        public let count: UInt
        public let sessionId: String
        public let documentId: DOCUMENT_ID
        public let data: Data

        public init(
            senderId: PEER_ID,
            targetId: PEER_ID,
            count: UInt,
            sessionId: String,
            documentId: DOCUMENT_ID,
            data: Data
        ) {
            self.senderId = senderId
            self.targetId = targetId
            self.count = count
            self.sessionId = sessionId
            self.documentId = documentId
            self.data = data
        }

        public var debugDescription: String {
            "EPHEMERAL[documentId: \(documentId), sender: \(senderId), target: \(targetId), count: \(count), sessionId: \(sessionId), data: \(data.count) bytes]"
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

    struct RemoteSubscriptionChangeMsg: Codable, CustomDebugStringConvertible {
        public var type = SyncV1.MsgTypes.remoteSubscriptionChange
        public let senderId: PEER_ID
        public let targetId: PEER_ID
        public var add: [STORAGE_ID]?
        public var remove: [STORAGE_ID]

        public init(senderId: PEER_ID, targetId: PEER_ID, add: [STORAGE_ID]? = nil, remove: [STORAGE_ID]) {
            self.senderId = senderId
            self.targetId = targetId
            self.add = add
            self.remove = remove
        }

        public var debugDescription: String {
            var returnString = "REMOTE_SUBSCRIPTION_CHANGE[sender: \(senderId), target: \(targetId)]"
            if let add {
                returnString.append("\n  add: [")
                returnString.append(add.joined(separator: ","))
                returnString.append("]")
            }
            returnString.append("\n  remove: [")
            returnString.append(remove.joined(separator: ","))
            returnString.append("]")
            return returnString
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

    struct RemoteHeadsChangedMsg: Codable, CustomDebugStringConvertible {
        public struct HeadsAtTime: Codable, CustomDebugStringConvertible {
            public var heads: [String]
            public let timestamp: uint

            public init(heads: [String], timestamp: uint) {
                self.heads = heads
                self.timestamp = timestamp
            }

            public var debugDescription: String {
                "\(timestamp):[\(heads.joined(separator: ","))]"
            }
        }

        public var type = SyncV1.MsgTypes.remoteHeadsChanged
        public let senderId: PEER_ID
        public let targetId: PEER_ID
        public let documentId: DOCUMENT_ID
        public var newHeads: [STORAGE_ID: HeadsAtTime]
        public var add: [STORAGE_ID]
        public var remove: [STORAGE_ID]

        public init(
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

        public var debugDescription: String {
            var returnString =
                "REMOTE_HEADS_CHANGED[documentId: \(documentId), sender: \(senderId), target: \(targetId)]"
            returnString.append("\n  heads:")
            for (storage_id, headsAtTime) in newHeads {
                returnString.append("\n    \(storage_id) : \(headsAtTime.debugDescription)")
            }
            returnString.append("\n  add: [")
            returnString.append(add.joined(separator: ", "))
            returnString.append("]")

            returnString.append("\n  remove: [")
            returnString.append(remove.joined(separator: ", "))
            returnString.append("]")
            return returnString
        }
    }
}
