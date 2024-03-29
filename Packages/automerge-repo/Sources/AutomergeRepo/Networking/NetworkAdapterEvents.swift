public struct PeerConnection: Sendable, CustomStringConvertible {
    public var description: String {
        if let meta = self.peerMetadata {
            "\(peerId),\(meta)"
        } else {
            "\(peerId),nil"
        }
    }

    public let peerId: PEER_ID
    public let peerMetadata: PeerMetadata?

    public init(peerId: PEER_ID, peerMetadata: PeerMetadata?) {
        self.peerId = peerId
        self.peerMetadata = peerMetadata
    }
}

public enum NetworkAdapterEvents: Sendable, CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .ready(payload):
            "NetworkAdapterEvents.ready[\(payload)]"
        case .close:
            "NetworkAdapterEvents.close[]"
        case let .peerCandidate(payload):
            "NetworkAdapterEvents.peerCandidate[\(payload)]"
        case let .peerDisconnect(payload):
            "NetworkAdapterEvents.peerDisconnect[\(payload)]"
        case let .message(payload):
            "NetworkAdapterEvents.message[\(payload)]"
        }
    }

    public struct PeerDisconnectPayload: Sendable, CustomStringConvertible {
        public var description: String {
            "\(peerId)"
        }

        // handled by Repo, relevant to Sync
        let peerId: PEER_ID

        public init(peerId: PEER_ID) {
            self.peerId = peerId
        }
    }

    case ready(payload: PeerConnection) // a network connection has been established and peered - sent by both listening
    // and initiating connections
    case close // handled by Repo, relevant to sync
    case peerCandidate(payload: PeerConnection) // sent when a listening network adapter receives a proposed connection
    // message (aka 'join')
    case peerDisconnect(payload: PeerDisconnectPayload) // send when a peer connection terminates
    case message(payload: SyncV1Msg) // handled by Sync
}

// network connection overview:
// - connection established
// - initiating side sends "join" message
// - receiving side send "peer" message
// ONLY after peer message is received is the connection considered valid

// for an outgoing connection:
// - network is ready for action
// - connect(to: SOMETHING)
// - when it receives the "peer" message, it's ready for ongoing work

// for an incoming connection:
// - network is ready for action
// - remove peer opens a connection, we receive a "join" message
// - (peer candidate is known at that point)
// - if all is good (version matches, etc) then we send "peer" message to acknowledge
// - after that, we're ready to process protocol messages
