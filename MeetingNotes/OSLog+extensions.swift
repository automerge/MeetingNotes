import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static var subsystem = Bundle.main.bundleIdentifier!

    /// Logs the Document interactions, such as saving and loading.
    static let document = Logger(subsystem: subsystem, category: "document")

    /// Logs updates and interaction related to watching for external peer systems.
    static let peerbrowser = Logger(subsystem: subsystem, category: "PeerBrowser")

    /// Logs updates and interaction related to listening connections from external peer systems.
    static let peerlistener = Logger(subsystem: subsystem, category: "PeerListener")

    /// Logs updates and interaction related to managing connections from external peer systems.
    static let syncconnection = Logger(subsystem: subsystem, category: "SyncConnection")

    /// Logs updates and interaction related to the process of synchronization over the network.
    static let syncprotocol = Logger(subsystem: subsystem, category: "SyncProtocol")

    /// All logs related to tracking and analytics.
    static let statistics = Logger(subsystem: subsystem, category: "statistics")
}
