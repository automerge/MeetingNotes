import Base58Swift
import Foundation
import XCTest

extension UUID {
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

    func testFiddlingWithBase58() throws {
        let exampleUUID = UUID()
        let bytes: Data = exampleUUID.data
        print(bytes.count)

        // let full = "automerge:2j9knpCseyhnK8izDmLpGP5WMdZQ"
        let partial = "2j9knpCseyhnK8izDmLpGP5WMdZQ"
        if let decodedBytes = Base58.base58CheckDecode(partial) {
            print(decodedBytes.count)
            // both are 16 bytes of data
            XCTAssertEqual(bytes.count, Data(decodedBytes).count)
        }
    }
}
