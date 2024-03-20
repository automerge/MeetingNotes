import Automerge
@testable import AutomergeRepo
import XCTest

final class StorageSubsystemTests: XCTestCase {
    var subsystem: DocumentStorage!
    var testStorageProvider: InMemoryStorage?

    override func setUp() async throws {
        let storageProvider = await InMemoryStorage()
        let incrementalKeys = await storageProvider.incrementalKeys()
        let docIds = await storageProvider.storageKeys()
        XCTAssertEqual(docIds.count, 0)
        XCTAssertEqual(incrementalKeys.count, 0)

        subsystem = DocumentStorage(storageProvider)
        testStorageProvider = storageProvider
    }

    func assertCounts(docIds: Int, incrementals: Int) async {
        let countOfIncrementalKeys = await testStorageProvider?.incrementalKeys().count
        let countOfDocumentIdKeys = await testStorageProvider?.storageKeys().count
        XCTAssertEqual(countOfDocumentIdKeys, docIds)
        XCTAssertEqual(countOfIncrementalKeys, incrementals)
    }

    func docDataSize(id: DocumentId) async -> Int {
        await testStorageProvider?.load(id: id)?.count ?? 0
    }

    func combinedIncData(id: DocumentId) async -> Int {
        if let inc = await testStorageProvider?.loadRange(id: id, prefix: subsystem.chunkNamespace) {
            return inc.reduce(0) { partialResult, data in
                partialResult + data.count
            }
        }
        return 0
    }

    func testSubsystemSetup() async throws {
        XCTAssertNotNil(subsystem)
        let newDoc = Document()
        let newDocId = DocumentId()

        try await subsystem.saveDoc(id: newDocId, doc: newDoc)
        await assertCounts(docIds: 0, incrementals: 1)

        let combinedKeys = await testStorageProvider?.incrementalKeys()
        XCTAssertEqual(combinedKeys?.count, 1)
        XCTAssertEqual(combinedKeys?[0].id, newDocId)
        XCTAssertEqual(combinedKeys?[0].prefix, "incrChanges")
        let incData = await testStorageProvider?.loadRange(id: newDocId, prefix: "incrChanges")
        let incDataUnwrapped = try XCTUnwrap(incData)
        XCTAssertEqual(incDataUnwrapped.count, 1)
        XCTAssertEqual(incDataUnwrapped[0].count, 0)

        let txt = try newDoc.putObject(obj: .ROOT, key: "words", ty: .Text)
        try await subsystem.saveDoc(id: newDocId, doc: newDoc)

        await assertCounts(docIds: 0, incrementals: 1)
        var incSize = await combinedIncData(id: newDocId)
        XCTAssertEqual(incSize, 58)

        try newDoc.updateText(obj: txt, value: "Hello World!")
        try await subsystem.saveDoc(id: newDocId, doc: newDoc)

        await assertCounts(docIds: 1, incrementals: 1)
        incSize = await combinedIncData(id: newDocId)
        var docSize = await docDataSize(id: newDocId)
        XCTAssertEqual(docSize, 121)
        XCTAssertEqual(incSize, 0)

        try await subsystem.compact(id: newDocId, doc: newDoc)

        await assertCounts(docIds: 1, incrementals: 1)
        incSize = await combinedIncData(id: newDocId)
        docSize = await docDataSize(id: newDocId)
        XCTAssertEqual(docSize, 121)
        XCTAssertEqual(incSize, 0)
        if let incrementals = await testStorageProvider?.loadRange(id: newDocId, prefix: subsystem.chunkNamespace) {
            print(incrementals)
        }
    }
}
