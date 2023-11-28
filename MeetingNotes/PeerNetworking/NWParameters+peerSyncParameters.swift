/*

 Copyright © 2022 Apple Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

  WWDC Video references aligned with this code:
  - https://developer.apple.com/videos/play/wwdc2019/713/
  - https://developer.apple.com/videos/play/wwdc2020/10110/
  */

import CryptoKit
import Network

extension NWParameters {
    /// Returns listener and connection network parameters using default TLS for peer to peer connections.
    static func peerSyncParameters(documentId: DocumentId) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let params = NWParameters(tls: tlsOptions(passcode: documentId.description), tcp: tcpOptions)
        let syncOptions = NWProtocolFramer.Options(definition: AutomergeSyncProtocol.definition)
        params.defaultProtocolStack.applicationProtocols.insert(syncOptions, at: 0)

        params.includePeerToPeer = true
        return params
    }

    // Create TLS options using a passcode to derive a pre-shared key.
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
        // Forcing non-standard cipher suite value to UInt16 because for
        // whatever reason, it can get returned as UInt32 - such as in
        // GitHub actions CI.
        let ciphersuiteValue = UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: ciphersuiteValue)!
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
