import Foundation

public extension SyncV1Msg {
    enum Errors {
        public struct Timeout: LocalizedError {
            public var errorDescription: String? = "Task timed out before completion"
        }

        public struct SyncComplete: LocalizedError {
            public var errorDescription: String? = "The synchronization process is complete"
        }

        public struct ConnectionClosed: LocalizedError {
            public var errorDescription: String? = "The websocket task was closed and/or nil"
        }

        public struct InvalidURL: LocalizedError {
            public let urlString: String
            public var errorDescription: String? {
                "Invalid URL: \(urlString)"
            }
        }

        public struct UnexpectedMsg<MSG>: LocalizedError {
            public let msg: MSG
            public var errorDescription: String? {
                "Received an unexpected message: \(msg)"
            }
        }

        public struct DocumentUnavailable: LocalizedError {
            public var errorDescription: String? = "The requested document isn't available"
        }
    }
}
