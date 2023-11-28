import Foundation

struct DocumentId: Hashable, Comparable, Identifiable {
    let id: String

    /// Creates a new, random document Id.
    init() {
        id = UUID().bs58String
    }

    /// Creates a document Id from a UUID v4
    /// - Parameter id: the v4 UUID to use as a document id.
    init(_ id: UUID) {
        self.id = id.bs58String
    }

    /// Creates a document Id from an optional string if the optional string is not null.
    /// - Parameter id: The string to use as a document id.
    init?(_ id: String?) {
        if let id {
            self.id = id
        } else {
            return nil
        }
    }

    /// Creates a document Id from a string.
    /// - Parameter id: The string to use as a document id.
    init(_ id: String) {
        self.id = id
        // Open Question(heckj): Should this be a throwable or fail-able initializer that verifies
        // the string represents exactly 16 bytes, in bs58 encoding?
    }

    // Comparable conformance
    static func < (lhs: DocumentId, rhs: DocumentId) -> Bool {
        lhs.id < rhs.id
    }
}

extension DocumentId: Codable {}

extension DocumentId: CustomStringConvertible {
    /// The string representation of the Document Id
    var description: String {
        id
    }
}
