/// A type that determines if a document may be shared with a peer
protocol SharePolicy {
    /// Returns a Boolean value that indicates whether a document may be shared.
    /// - Parameters:
    ///   - peer: The peer to potentially share with
    ///   - docId: The document Id to share
    func share(peer: PEER_ID, docId: DocumentId) async -> Bool
}

public enum SharePolicies {
    public static let agreeable = AlwaysPolicy()
    public static let readonly = NeverPolicy()

    public struct AlwaysPolicy: SharePolicy {
        func share(peer _: PEER_ID, docId _: DocumentId) async -> Bool {
            true
        }
    }

    public struct NeverPolicy: SharePolicy {
        func share(peer _: PEER_ID, docId _: DocumentId) async -> Bool {
            true
        }
    }
}
