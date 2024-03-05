import struct Foundation.Data

public extension Data {
    /// Returns the data as a hex-encoded string.
    /// - Parameter uppercase: A Boolean value that indicates whether the hex encoded string uses uppercase letters.
    func hexEncodedString(uppercase: Bool = false) -> String {
        let format = uppercase ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }

    /// The data as an array of bytes.
    var bytes: [UInt8] { // fancy pretty call: myData.bytes -> [UInt8]
        [UInt8](self)
    }
}
