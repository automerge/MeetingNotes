import Foundation

extension Repo {
    enum Errors {
        public struct Unavailable: LocalizedError {
            let id: DocumentId
            public var errorDescription: String? {
                "Unknown document Id: \(self.id)"
            }
        }

        public struct DocDeleted: LocalizedError {
            let id: DocumentId
            public var errorDescription: String? {
                "Document with Id: \(self.id) has been deleted."
            }
        }

        public struct DocUnavailable: LocalizedError {
            let id: DocumentId
            public var errorDescription: String? {
                "Document with Id: \(self.id) is unavailable."
            }
        }

        public struct BigBadaBoom: LocalizedError {
            let msg: String
            public var errorDescription: String? {
                "Something went quite wrong: \(self.msg)."
            }
        }

    }
}
