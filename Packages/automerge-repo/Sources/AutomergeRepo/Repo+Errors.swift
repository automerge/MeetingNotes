import Foundation

extension Repo {
    enum Errors: Sendable {
        public struct Unavailable: Sendable, LocalizedError {
            let id: DocumentId
            public var errorDescription: String? {
                "Unknown document Id: \(self.id)"
            }
        }

        public struct DocDeleted: Sendable, LocalizedError {
            let id: DocumentId
            public var errorDescription: String? {
                "Document with Id: \(self.id) has been deleted."
            }
        }

        public struct DocUnavailable: Sendable, LocalizedError {
            let id: DocumentId
            public var errorDescription: String? {
                "Document with Id: \(self.id) is unavailable."
            }
        }

        public struct BigBadaBoom: Sendable, LocalizedError {
            let msg: String
            public var errorDescription: String? {
                "Something went quite wrong: \(self.msg)."
            }
        }

    }
}
