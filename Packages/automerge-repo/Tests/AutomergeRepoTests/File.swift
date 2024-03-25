@testable import AutomergeRepo
import Base58Swift
import XCTest

final class BS58IdTests: XCTestCase {
    func testDataLengthUUIDandAutomergeID() throws {
        let exampleUUID = UUID()
        let bytes: Data = exampleUUID.data
        // example from AutomergeRepo docs/blog
        // https://automerge.org/blog/2023/11/06/automerge-repo/
        // let full = "automerge:2j9knpCseyhnK8izDmLpGP5WMdZQ"
        let partial = "2j9knpCseyhnK8izDmLpGP5WMdZQ"
        XCTAssertEqual(Base58.base58Decode(partial)?.count, 20)
        if let decodedBytes = Base58.base58CheckDecode(partial) {
            // both are 16 bytes of data
            XCTAssertEqual(bytes.count, Data(decodedBytes).count)
        }
    }

    func testDisplayingUUIDWithBase58() throws {
        let exampleUUID = try XCTUnwrap(UUID(uuidString: "1654A0B5-43B9-48FF-B7FB-83F58F4D1D75"))
        // print("hexencoded: \(exampleUUID.data.hexEncodedString())")
        XCTAssertEqual("1654a0b543b948ffb7fb83f58f4d1d75", exampleUUID.data.hexEncodedString())
        let bs58Converted = Base58.base58CheckEncode(exampleUUID.data.bytes)
        // print("Converted: \(bs58Converted)")
        XCTAssertEqual("K3YptshN5CcFZNpnnXcStizSNPU", bs58Converted)
        XCTAssertEqual(exampleUUID.bs58String, bs58Converted)
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
