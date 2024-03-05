import Base58Swift
import struct Foundation.Data
import struct Foundation.UUID

public extension UUID {
    /// The contents of the UUID as data.
    var data: Data {
        var byteblob = Data(count: 16)
        byteblob[0] = self.uuid.0
        byteblob[1] = self.uuid.1
        byteblob[2] = self.uuid.2
        byteblob[3] = self.uuid.3
        byteblob[4] = self.uuid.4
        byteblob[5] = self.uuid.5
        byteblob[6] = self.uuid.6
        byteblob[7] = self.uuid.7
        byteblob[8] = self.uuid.8
        byteblob[9] = self.uuid.9
        byteblob[10] = self.uuid.10
        byteblob[11] = self.uuid.11
        byteblob[12] = self.uuid.12
        byteblob[13] = self.uuid.13
        byteblob[14] = self.uuid.14
        byteblob[15] = self.uuid.15
        return byteblob
    }

    /// The contents of UUID as a BS58 encoded string.
    var bs58String: String {
        Base58.base58CheckEncode(self.data.bytes)
    }
}
