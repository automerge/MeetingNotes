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

        let invalidOptionalString: String? = "SomeRandomNonBS58String"
        XCTAssertNil(DocumentId(invalidOptionalString))

        let invalidString = "SomeRandomNonBS58String"
        XCTAssertNil(DocumentId(invalidString))

        let optionalString: String? = bs58String
        XCTAssertEqual(DocumentId(optionalString)?.description, bs58String)

        XCTAssertNil(DocumentId(nil))
    }

    func testInvalidTooMuchDataDocumentId() async throws {
        let tooBig = [UInt8](UUID().data + UUID().data)
        let bs58StringFromData = Base58.base58CheckEncode(tooBig)
        let tooLargeOptionalString: String? = bs58StringFromData
        XCTAssertNil(DocumentId(bs58StringFromData))
        XCTAssertNil(DocumentId(tooLargeOptionalString))

        let optionalString: String? = bs58StringFromData
        XCTAssertNil(DocumentId(optionalString))
    }

    func testComparisonOnData() async throws {
        let first = DocumentId()
        let second = DocumentId()
        let compareFirstAndSecond = first < second
        let compareFirstAndSecondDescription = first.description < second.description
        XCTAssertEqual(compareFirstAndSecond, compareFirstAndSecondDescription)
    }
}
