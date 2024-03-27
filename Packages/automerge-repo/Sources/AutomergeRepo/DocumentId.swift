import Base58Swift
import struct Foundation.Data
import struct Foundation.UUID

/// A type that represents an Automerge-repo compatible document identifier
public struct DocumentId: Sendable, Hashable, Comparable, Identifiable {
    /// A bs58 encoded string that represents the identifier
    public let id: String
    // Data?
    // [UInt8]

    /// Creates a new, random document identifier.
    public init() {
        id = UUID().bs58String
    }

    /// Creates a document identifier from a UUID v4
    /// - Parameter id: the v4 UUID to use as a document identifier.
    public init(_ id: UUID) {
        self.id = id.bs58String
    }

    /// Creates a document identifier from an optional string.
    /// - Parameter id: The string to use as a document identifier.
    public init?(_ id: String?) {
        guard let id else {
            return nil
        }
        guard let uint_array = Base58.base58CheckDecode(id) else {
            return nil
        }
        if uint_array.count != 16 {
            return nil
        }
        self.id = id
    }

    /// Creates a document identifier from a string.
    /// - Parameter id: The string to use as a document identifier.
    public init?(_ id: String) {
        guard let uint_array = Base58.base58CheckDecode(id) else {
            return nil
        }
        if uint_array.count != 16 {
            return nil
        }
        self.id = id
    }

    // Comparable conformance
    public static func < (lhs: DocumentId, rhs: DocumentId) -> Bool {
        lhs.id < rhs.id
    }
}

extension DocumentId: Codable {}

extension DocumentId: CustomStringConvertible {
    /// The string representation of the Document identifier
    public var description: String {
        id
    }
}
