import Automerge
@testable import AutomergeRepo
import XCTest

final class DocHandleTests: XCTestCase {
    func testNewDocHandleData() async throws {
        let id = DocumentId()
        let new = InternalDocHandle(id: id, isNew: true)

        XCTAssertEqual(new.id, id)
        XCTAssertEqual(new.state, .idle)
        XCTAssertEqual(new.isDeleted, false)
        XCTAssertEqual(new.isReady, false)
        XCTAssertEqual(new.isUnavailable, false)
        XCTAssertEqual(new.remoteHeads.count, 0)
        XCTAssertNil(new.doc)
    }

    func testNewDocHandleDataWithDocument() async throws {
        let id = DocumentId()
        let new = InternalDocHandle(id: id, isNew: true, initialValue: Document())

        XCTAssertEqual(new.id, id)
        XCTAssertEqual(new.state, .loading)
        XCTAssertEqual(new.isDeleted, false)
        XCTAssertEqual(new.isReady, false)
        XCTAssertEqual(new.isUnavailable, false)
        XCTAssertEqual(new.remoteHeads.count, 0)
        XCTAssertNotNil(new.doc)
    }

    func testDocHandleRequestData() async throws {
        let id = DocumentId()
        let new = InternalDocHandle(id: id, isNew: false)

        XCTAssertEqual(new.id, id)
        XCTAssertEqual(new.state, .idle)
        XCTAssertEqual(new.isDeleted, false)
        XCTAssertEqual(new.isReady, false)
        XCTAssertEqual(new.isUnavailable, false)
        XCTAssertEqual(new.remoteHeads.count, 0)
        XCTAssertNil(new.doc)
    }

    func testDocHandleRequestDataWithData() async throws {
        let id = DocumentId()
        let new = InternalDocHandle(id: id, isNew: false, initialValue: Document())

        XCTAssertEqual(new.id, id)
        XCTAssertEqual(new.state, .ready)
        XCTAssertEqual(new.isDeleted, false)
        XCTAssertEqual(new.isReady, true)
        XCTAssertEqual(new.isUnavailable, false)
        XCTAssertEqual(new.remoteHeads.count, 0)
        XCTAssertNotNil(new.doc)
    }
}
