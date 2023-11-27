import Base58Swift
import Foundation
import XCTest

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
        
    func hexEncodedString(uppercase: Bool = false) -> String {
        let format = uppercase ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
}

extension UUID {
    var uintArray: [UInt8] {
        var byteblob = [UInt8](repeating: 0, count: 16)
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
}

final class MeetingNotesTests: XCTestCase {
    override func setUpWithError() throws {
        // This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // This method is called after the invocation of each test method in the class.
    }

    func testDataLengthUUIDandAutomergeID() throws {
        let exampleUUID = UUID()
        let bytes: Data = exampleUUID.data
        // let full = "automerge:2j9knpCseyhnK8izDmLpGP5WMdZQ"
        let partial = "2j9knpCseyhnK8izDmLpGP5WMdZQ"
        if let decodedBytes = Base58.base58CheckDecode(partial) {
            // both are 16 bytes of data
            XCTAssertEqual(bytes.count, Data(decodedBytes).count)
        }
    }
    
    func testDisplayingUUIDWithBase58() throws {
        let exampleUUID = try XCTUnwrap(UUID(uuidString: "1654A0B5-43B9-48FF-B7FB-83F58F4D1D75"))
        // print("hexencoded: \(exampleUUID.data.hexEncodedString())")
        XCTAssertEqual("1654a0b543b948ffb7fb83f58f4d1d75", exampleUUID.data.hexEncodedString())
        let bs58Converted = Base58.base58CheckEncode(exampleUUID.uintArray)
        // print("Converted: \(bs58Converted)")
        XCTAssertEqual("K3YptshN5CcFZNpnnXcStizSNPU", bs58Converted)
    }

    func testDataInAndOutWithBase58() throws {
        // let full = "automerge:2j9knpCseyhnK8izDmLpGP5WMdZQ"
        let partial = "2j9knpCseyhnK8izDmLpGP5WMdZQ"
        if let decodedBytes = Base58.base58CheckDecode(partial) {
            print(decodedBytes.count)
            // AutomergeID is 16 bytes of data
            XCTAssertEqual(16, Data(decodedBytes).count)
            XCTAssertEqual("7bf18580944c450ea740c1f23be047ca", Data(decodedBytes).hexEncodedString())
            // print(Data(decodedBytes).hexEncodedString())
            
            let reversed = Base58.base58CheckEncode(decodedBytes)
            XCTAssertEqual(reversed, partial)
        }
    }
}
