import CryptoKit
import Network

extension NWParameters {
    /// Returns listener and connection network parameters using default TLS for peer to peer connections.
    static func peerSyncParameters(documentId: String) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let params = NWParameters(tls: tlsOptions(passcode: documentId), tcp: tcpOptions)
        let syncOptions = NWProtocolFramer.Options(definition: AutomergeSyncProtocol.definition)
        params.defaultProtocolStack.applicationProtocols.insert(syncOptions, at: 0)

        params.includePeerToPeer = true
        return params
    }

    // Create TLS options using a passcode to derive a preshared key.
    private static func tlsOptions(passcode: String) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()

        let authenticationKey = SymmetricKey(data: passcode.data(using: .utf8)!)
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: "MeetingNotes".data(using: .utf8)!,
            using: authenticationKey
        )

        let authenticationDispatchData = authenticationCode.withUnsafeBytes {
            DispatchData(bytes: $0)
        }

        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            authenticationDispatchData as __DispatchData,
            stringToDispatchData("MeetingNotes")! as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!
        )
        return tlsOptions
    }

    // Create a utility function to encode strings as preshared key data.
    private static func stringToDispatchData(_ string: String) -> DispatchData? {
        guard let stringData = string.data(using: .utf8) else {
            return nil
        }
        let dispatchData = stringData.withUnsafeBytes {
            DispatchData(bytes: $0)
        }
        return dispatchData
    }
}
