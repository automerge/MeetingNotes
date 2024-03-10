public enum NetworkAdapterEvents: Sendable {
//    public struct OpenPayload {
//        let network: any NetworkProvider // do we need this payload? What's repo going to do with it?
//    }

    public struct PeerCandidatePayload: Sendable { // handled by Repo - relevant to storage
        let peerId: PEER_ID
        let peerMetadata: PeerMetadata
    }

    public struct PeerDisconnectPayload: Sendable { // handled by Repo, relevant to Sync
        let peerId: PEER_ID
    }

    case ready // (payload: OpenPayload) // repo only
    case close // handled by Repo, relevant to sync
    case peerCandidate(payload: PeerCandidatePayload) // handled by Repo
    case peerDisconnect(payload: PeerDisconnectPayload) // handled by Repo, relevant to Sync
    case message(payload: SyncV1Msg) // handled by Sync
}
