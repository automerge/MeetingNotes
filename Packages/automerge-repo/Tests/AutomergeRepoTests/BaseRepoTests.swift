import Automerge
@testable import AutomergeRepo
import AutomergeUtilities
import XCTest

final class BaseRepoTests: XCTestCase {
    var repo: Repo!

    override func setUp() async throws {
        repo = Repo(sharePolicy: SharePolicies.agreeable)
    }

    func testMostBasicRepoStartingPoints() async throws {
        // Repo
        //  property: peers [PeerId] - all (currently) connected peers
        let peers = await repo.peers()
        XCTAssertEqual(peers, [])

        // let peerId = await repo.peerId
        // print(peerId)

        // - func storageId() -> StorageId (async)
        let storageId = await repo.storageId()
        XCTAssertNil(storageId)

        let knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds, [])
    }

    func testCreate() async throws {
        let newDoc = try await repo.create()
        XCTAssertNotNil(newDoc)
        let knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 1)
    }

    func testCreateWithId() async throws {
        let myId = DocumentId()
        let handle = try await repo.create(id: myId)
        XCTAssertEqual(myId, handle.id)

        let knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 1)
        XCTAssertEqual(knownIds[0], myId)
    }

    func testCreateWithExistingDoc() async throws {
        let handle = try await repo.create(doc: Document())
        var knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 1)
        XCTAssertEqual(knownIds[0], handle.id)

        let myId = DocumentId()
        let _ = try await repo.create(doc: Document(), id: myId)
        knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 2)
    }

    func testFind() async throws {
        let myId = DocumentId()
        let handle = try await repo.create(id: myId)
        XCTAssertEqual(myId, handle.id)

        let foundDoc = try await repo.find(id: myId)
        XCTAssertEqual(foundDoc.doc.actor, handle.doc.actor)
    }

    func testFindFailed() async throws {
        do {
            let _ = try await repo.find(id: DocumentId())
            XCTFail()
        } catch {}
    }

    func testDelete() async throws {
        let myId = DocumentId()
        let _ = try await repo.create(id: myId)
        var knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 1)

        try await repo.delete(id: myId)
        knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 0)

        do {
            let _ = try await repo.find(id: DocumentId())
            XCTFail()
        } catch {}
    }

    func testClone() async throws {
        let myId = DocumentId()
        let handle = try await repo.create(id: myId)
        XCTAssertEqual(myId, handle.id)

        let clonedHandle = try await repo.clone(id: myId)
        XCTAssertNotEqual(handle.id, clonedHandle.id)
        XCTAssertNotEqual(handle.doc.actor, clonedHandle.doc.actor)

        let knownIds = await repo.documentIds()
        XCTAssertEqual(knownIds.count, 2)
    }

    func testExportFailureUnknownId() async throws {
        do {
            _ = try await repo.export(id: DocumentId())
            XCTFail()
        } catch {}
    }

    func testExport() async throws {
        let newDoc = try RepoHelpers.documentWithData()
        let newHandle = try await repo.create(doc: newDoc)

        let exported = try await repo.export(id: newHandle.id)
        XCTAssertEqual(exported, newDoc.save())
    }

    func testImport() async throws {
        let newDoc = try RepoHelpers.documentWithData()

        let handle = try await repo.import(data: newDoc.save())
        XCTAssertTrue(RepoHelpers.equalContents(doc1: handle.doc, doc2: newDoc))
    }

    // TBD:
    // - func storageIdForPeer(peerId) -> StorageId
    // - func subscribeToRemotes([StorageId])

    func testRepoSetup() async throws {
        let repoA = Repo(sharePolicy: SharePolicies.agreeable)
        let storage = await InMemoryStorage()
        await repoA.addStorageProvider(storage)

        let storageId = await repoA.storageId()
        XCTAssertNotNil(storageId)
    }
}
