import OSLog

extension Logger: @unchecked Sendable {}
// https://forums.developer.apple.com/forums/thread/747816?answerId=781922022#781922022
// Per Quinn:
// `Logger` should be sendable. Under the covers, it’s an immutable struct with a single
// OSLog property, and that in turn is just a wrapper around the C os_log_t which is
// definitely thread safe.
#if swift(>=6.0)
#warning("Reevaluate whether this decoration is necessary.")
#endif

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// Logs updates and interaction related to watching for external peer systems.
    static let syncController = Logger(subsystem: subsystem, category: "SyncController")

    /// Logs updates and interaction related to the process of synchronization over the network.
    static let syncConnection = Logger(subsystem: subsystem, category: "SyncConnection")

    /// Logs updates and interaction related to the process of synchronization over the network.
    static let webSocket = Logger(subsystem: subsystem, category: "WebSocket")

    /// Logs updates and interaction related to the process of synchronization over the network.
    static let storage = Logger(subsystem: subsystem, category: "storageSubsystem")

    static let repo = Logger(subsystem: subsystem, category: "automerge-repo")

    static let network = Logger(subsystem: subsystem, category: "networkSubsystem")
}
