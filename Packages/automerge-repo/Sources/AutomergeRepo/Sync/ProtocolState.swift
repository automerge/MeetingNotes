/// The state of a sync protocol connection.
public enum ProtocolState: String {
    /// The connection that has been created but not yet connected
    case setup

    /// The connection is established, waiting to successfully peer with the recipient.
    case preparing

    /// The connection successfully peered and is ready for use.
    case ready

    /// The connection is cancelled, failed, or terminated.
    case closed
}

#if canImport(Network)
import class Network.NWConnection

extension ProtocolState {
    /// Translates a Network connection state into a protocol state
    /// - Parameter connectState: The state of the network connection
    /// - Returns: The corresponding protocol state
    func from(_ connectState: NWConnection.State) -> Self {
        switch connectState {
        case .setup:
            .setup
        case .waiting:
            .preparing
        case .preparing:
            .preparing
        case .ready:
            .ready
        case .failed:
            .closed
        case .cancelled:
            .closed
        @unknown default:
            fatalError()
        }
    }
}
#endif
