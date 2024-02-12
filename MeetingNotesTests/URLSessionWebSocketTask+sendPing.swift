import Foundation

extension URLSessionWebSocketTask {
    struct WebSocketPingError: LocalizedError {
        var errorDescription: String {
            "WebSocket ping() returned an error: \(wrappedError.localizedDescription)"
        }

        let wrappedError: any Error
        init(wrappedError: any Error) {
            self.wrappedError = wrappedError
        }
    }

    func sendPing() async throws {
        let _: Bool = try await withCheckedThrowingContinuation { continuation in
            self.sendPing { err in
                if let err {
                    continuation.resume(throwing: WebSocketPingError(wrappedError: err))
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
