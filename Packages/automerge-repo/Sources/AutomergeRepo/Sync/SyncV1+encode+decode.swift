import Foundation // Data
import OSLog
import PotentCBOR

public extension SyncV1 {
    /// Attempts to decode the data you provide as a peer message.
    ///
    /// - Parameter data: The data to decode
    /// - Returns: The decoded message, or ``SyncV1/unknown(_:)`` if the decoding attempt failed.
    static func decodePeer(_ data: Data) -> SyncV1 {
        if let peerMsg = attemptPeer(data) {
            .peer(peerMsg)
        } else {
            .unknown(data)
        }
    }

    /// Decodes a Peer2Peer message data block using the message type you provide
    /// - Parameters:
    ///   - data: The data to be decoded
    ///   - msgType: The type of message to decode.
    /// - Returns: The decoded message.
    internal static func decode(_ data: Data, as msgType: P2PSyncMessageType) -> SyncV1 {
        switch msgType {
        case .unknown:
            return .unknown(data)
        case .sync:
            if let msgData = attemptSync(data) {
                return .sync(msgData)
            }
        case .id:
            return .unknown(data)
        case .peer:
            if let msgData = attemptPeer(data) {
                return .peer(msgData)
            }
        case .join:
            if let msgData = attemptJoin(data) {
                return .join(msgData)
            }
        case .request:
            if let msgData = attemptRequest(data) {
                return .request(msgData)
            }
        case .unavailable:
            if let msgData = attemptUnavailable(data) {
                return .unavailable(msgData)
            }
        case .ephemeral:
            if let msgData = attemptEphemeral(data) {
                return .ephemeral(msgData)
            }
        case .syncerror:
            if let msgData = attemptError(data) {
                return .error(msgData)
            }
        case .remoteHeadsChanged:
            if let msgData = attemptRemoteHeadsChanged(data) {
                return .remoteHeadsChanged(msgData)
            }
        case .remoteSubscriptionChange:
            if let msgData = attemptRemoteSubscriptionChange(data) {
                return .remoteSubscriptionChange(msgData)
            }
        }
        return .unknown(data)
    }

    /// Exhaustively attempt to decode incoming data as V1 protocol messages.
    ///
    /// - Parameters:
    ///   - data: The data to decode.
    ///   - withGossip: A Boolean value that indicates whether to include decoding of handshake messages.
    ///   - withHandshake: A Boolean value that indicates whether to include decoding of gossip messages.
    /// - Returns: The decoded message, or ``SyncV1/unknown(_:)`` if the previous decoding attempts failed.
    ///
    /// The decoding is ordered from the perspective of an initiating client expecting a response to minimize attempts.
    /// Enable `withGossip` to attempt to decode head gossip messages, and `withHandshake` to include handshake phase
    /// messages.
    /// With both `withGossip` and `withHandshake` set to `true`, the decoding is exhaustive over all V1 messages.
    static func decode(_ data: Data) -> SyncV1 {
        var cborMsg: CBOR? = nil

        // attempt to deserialize CBOR message (in order to read the type from it)
        do {
            cborMsg = try CBORSerialization.cbor(from: data)
        } catch {
            Logger.webSocket.warning("Unable to CBOR decode incoming data: \(data)")
            return .unknown(data)
        }
        // read the "type" of the message in order to choose the appropriate decoding path
        guard let msgType = cborMsg?.mapValue?["type"]?.utf8StringValue else {
            return .unknown(data)
        }

        switch msgType {
        case MsgTypes.peer:
            if let peerMsg = attemptPeer(data) {
                return .peer(peerMsg)
            }
        case MsgTypes.sync:
            if let syncMsg = attemptSync(data) {
                return .sync(syncMsg)
            }
        case MsgTypes.ephemeral:
            if let ephemeralMsg = attemptEphemeral(data) {
                return .ephemeral(ephemeralMsg)
            }
        case MsgTypes.error:
            if let errorMsg = attemptError(data) {
                return .error(errorMsg)
            }
        case MsgTypes.unavailable:
            if let unavailableMsg = attemptUnavailable(data) {
                return .unavailable(unavailableMsg)
            }
        case MsgTypes.join:
            if let joinMsg = attemptJoin(data) {
                return .join(joinMsg)
            }
        case MsgTypes.remoteHeadsChanged:
            if let remoteHeadsChanged = attemptRemoteHeadsChanged(data) {
                return .remoteHeadsChanged(remoteHeadsChanged)
            }
        case MsgTypes.request:
            if let requestMsg = attemptRequest(data) {
                return .request(requestMsg)
            }
        case MsgTypes.remoteSubscriptionChange:
            if let remoteSubChangeMsg = attemptRemoteSubscriptionChange(data) {
                return .remoteSubscriptionChange(remoteSubChangeMsg)
            }

        default:
            return .unknown(data)
        }
        return .unknown(data)
    }

    // sync phase messages

    internal static func attemptSync(_ data: Data) -> SyncMsg? {
        do {
            return try decoder.decode(SyncMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as SyncMsg")
        }
        return nil
    }

    internal static func attemptRequest(_ data: Data) -> RequestMsg? {
        do {
            return try decoder.decode(RequestMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as RequestMsg")
        }
        return nil
    }

    internal static func attemptUnavailable(_ data: Data) -> UnavailableMsg? {
        do {
            return try decoder.decode(UnavailableMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as UnavailableMsg")
        }
        return nil
    }

    // handshake phase messages

    internal static func attemptPeer(_ data: Data) -> PeerMsg? {
        do {
            return try decoder.decode(PeerMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as PeerMsg")
        }
        return nil
    }

    internal static func attemptJoin(_ data: Data) -> JoinMsg? {
        do {
            return try decoder.decode(JoinMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as JoinMsg")
        }
        return nil
    }

    // error

    internal static func attemptError(_ data: Data) -> ErrorMsg? {
        do {
            return try decoder.decode(ErrorMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as ErrorMsg")
        }
        return nil
    }

    // ephemeral

    internal static func attemptEphemeral(_ data: Data) -> EphemeralMsg? {
        do {
            return try decoder.decode(EphemeralMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as EphemeralMsg")
        }
        return nil
    }

    // gossip

    internal static func attemptRemoteHeadsChanged(_ data: Data) -> RemoteHeadsChangedMsg? {
        do {
            return try decoder.decode(RemoteHeadsChangedMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as RemoteHeadsChangedMsg")
        }
        return nil
    }

    internal static func attemptRemoteSubscriptionChange(_ data: Data) -> RemoteSubscriptionChangeMsg? {
        do {
            return try decoder.decode(RemoteSubscriptionChangeMsg.self, from: data)
        } catch {
            Logger.webSocket.warning("Failed to decode data as RemoteSubscriptionChangeMsg")
        }
        return nil
    }

    // encode messages

    static func encode(_ msg: JoinMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: RequestMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: SyncMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: PeerMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: UnavailableMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: EphemeralMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: RemoteSubscriptionChangeMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: RemoteHeadsChangedMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: ErrorMsg) throws -> Data {
        try encoder.encode(msg)
    }

    static func encode(_ msg: SyncV1) throws -> Data {
        // not sure this is useful, but might as well finish out the set...
        switch msg {
        case let .peer(peerMsg):
            try encode(peerMsg)
        case let .join(joinMsg):
            try encode(joinMsg)
        case let .error(errorMsg):
            try encode(errorMsg)
        case let .request(requestMsg):
            try encode(requestMsg)
        case let .sync(syncMsg):
            try encode(syncMsg)
        case let .unavailable(unavailableMsg):
            try encode(unavailableMsg)
        case let .ephemeral(ephemeralMsg):
            try encode(ephemeralMsg)
        case let .remoteSubscriptionChange(remoteSubscriptionChangeMsg):
            try encode(remoteSubscriptionChangeMsg)
        case let .remoteHeadsChanged(remoteHeadsChangedMsg):
            try encode(remoteHeadsChangedMsg)
        case let .unknown(data):
            data
        }
    }
}
