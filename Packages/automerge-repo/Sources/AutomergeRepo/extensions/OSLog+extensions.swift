import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static var subsystem = Bundle.main.bundleIdentifier!

    /// Logs updates and interaction related to watching for external peer systems.
    static let syncController = Logger(subsystem: subsystem, category: "SyncController")

    /// Logs updates and interaction related to the process of synchronization over the network.
    static let syncConnection = Logger(subsystem: subsystem, category: "SyncConnection")

    /// Logs updates and interaction related to the process of synchronization over the network.
    static let webSocket = Logger(subsystem: subsystem, category: "WebSocket")
}
