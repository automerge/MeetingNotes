import Network

extension NWParameters {
    /// Returns listener and connection network parameters using default TLS for peer to peer connections.
    static func peerSyncParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        return NWParameters(tls: NWProtocolTLS.Options(), tcp: tcpOptions)
    }
}
