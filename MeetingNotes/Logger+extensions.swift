import Foundation
import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier!

    /// Logs the Document interactions, such as saving and loading.
    static let document = Logger(subsystem: subsystem, category: "Document")
}
