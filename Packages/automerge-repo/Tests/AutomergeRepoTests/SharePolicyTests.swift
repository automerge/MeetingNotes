@testable import AutomergeRepo
import XCTest

final class SharePolicyTests: XCTestCase {
    func testSharePolicy() async throws {
        let agreeableShareResult = await SharePolicies.agreeable.share(peer: "A", docId: DocumentId())
        XCTAssertTrue(agreeableShareResult)

        let readOnlyShareResult = await SharePolicies.readonly.share(peer: "A", docId: DocumentId())
        XCTAssertFalse(readOnlyShareResult)
    }
}
