@testable import AutomergeRepo
import Base58Swift
import XCTest

final class DocumentIdTests: XCTestCase {
    func testInvalidDocumentIdString() async throws {
        XCTAssertNil(DocumentId("some random string"))
    }

    func testDocumentId() async throws {
        let someUUID = UUID()
        let id = DocumentId(someUUID)
        XCTAssertEqual(id.description, someUUID.bs58String)
    }

    func testDocumentIdFromString() async throws {
        let someUUID = UUID()
        let bs58String = someUUID.bs58String
        let id = DocumentId(bs58String)
        XCTAssertEqual(id?.description, bs58String)

        let optionalString: String? = bs58String
        XCTAssertEqual(DocumentId(optionalString)?.description, bs58String)
    }

    func testInvalidTooMuchDataDocumentId() async throws {
        let tooBig = [UInt8](UUID().data + UUID().data)
        let bs58StringFromData = Base58.base58Encode(tooBig)
        XCTAssertNil(DocumentId(bs58StringFromData))

        let optionalString: String? = bs58StringFromData
        XCTAssertNil(DocumentId(optionalString))
    }
}
