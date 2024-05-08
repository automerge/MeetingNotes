import Foundation
import OSLog

// using : @unchecked Sendable here because I think Logger _is_ sendable,
// but isn't yet marked as such. Alternatively I think we could use @preconcurrency import,
// but doing this due to the conversation on the forums (Mar2024):
// https://forums.swift.org/t/preconcurrency-doesnt-suppress-static-property-concurrency-warnings/70469/2
extension Logger: @unchecked Sendable {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private nonisolated static let subsystem = Bundle.main.bundleIdentifier!

    /// Logs the Document interactions, such as saving and loading.
    static let document = Logger(subsystem: subsystem, category: "Document")

    /// Logs messages that pertain to sending or receiving sync updates.
    static let syncflow = Logger(subsystem: subsystem, category: "SyncFlow")
}
