import Foundation

public extension SyncV1Msg {
    enum Errors: Sendable {
        public struct Timeout: Sendable, LocalizedError {
            public var errorDescription: String = "Task timed out before completion"
        }

        public struct SyncComplete: Sendable, LocalizedError {
            public var errorDescription: String = "The synchronization process is complete"
        }

        public struct ConnectionClosed: Sendable, LocalizedError {
            public var errorDescription: String = "The websocket task was closed and/or nil"
        }

        public struct InvalidURL: Sendable, LocalizedError {
            public var urlString: String
            public var errorDescription: String? {
                "Invalid URL: \(urlString)"
            }
        }

        public struct UnexpectedMsg<MSG: Sendable>: Sendable, LocalizedError {
            public var msg: MSG
            public var errorDescription: String? {
                "Received an unexpected message: \(msg)"
            }
        }

        public struct DocumentUnavailable: Sendable, LocalizedError {
            public var errorDescription: String = "The requested document isn't available"
        }
    }
}
