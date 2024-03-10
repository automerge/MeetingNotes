import Foundation

// ; Metadata sent in either the join or peer message types
// peer_metadata = {
//    ; The storage ID of this peer
//    ? storageId: storage_id,
//    ; Whether the sender expects to connect again with this storage ID
//    isEphemeral: bool
// }

public struct PeerMetadata: Sendable, Codable, CustomDebugStringConvertible {
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
