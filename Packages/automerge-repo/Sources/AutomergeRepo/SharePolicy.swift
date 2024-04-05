/// A type that determines if a document may be shared with a peer
public protocol SharePolicy: Sendable {
    /// Returns a Boolean value that indicates whether a document may be shared.
    /// - Parameters:
    ///   - peer: The peer to potentially share with
    ///   - docId: The document Id to share
    func share(peer: PEER_ID, docId: DocumentId) async -> Bool
}

#warning("REWORK THIS SETUP")
// it's annoying as hell to have to specify the SharePolicies.agreeable kind of setup just to get
// this. Seems better to make SharePolicy a struct, rename the protocol to allow for
// generics/existential use, and add some static let variants onto the type itself.
public enum SharePolicies: Sendable {
    public static let agreeable = AlwaysPolicy()
    public static let readonly = NeverPolicy()

    public struct AlwaysPolicy: SharePolicy {
        public func share(peer _: PEER_ID, docId _: DocumentId) async -> Bool {
            true
        }
    }

    public struct NeverPolicy: SharePolicy {
        public func share(peer _: PEER_ID, docId _: DocumentId) async -> Bool {
            false
        }
    }
}
