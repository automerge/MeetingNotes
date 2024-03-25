import Automerge
@testable import AutomergeRepo
import AutomergeUtilities
import XCTest

final class TwoReposWithNetworkTests: XCTestCase {
    let network = InMemoryNetwork.shared
    var repoA: Repo!
    var repoB: Repo!

    var adapterA: InMemoryNetworkEndpoint!
    var adapterB: InMemoryNetworkEndpoint!

    override func setUp() async throws {
        await network.resetTestNetwork()
        repoA = Repo(sharePolicy: SharePolicies.agreeable)

        // Repo setup WITHOUT any storage subsystem
        let storageId = await repoA.storageId()
        XCTAssertNil(storageId)

        adapterA = await network.createNetworkEndpoint(
            config: .init(
                localPeerId: "onePeer",
                localMetaData: nil,
                listeningNetwork: false,
                name: "A"
            )
        )
        await repoA.addNetworkAdapter(adapter: adapterA)

        let peersA = await repoA.peers()
        XCTAssertEqual(peersA, [])

        repoB = Repo(sharePolicy: SharePolicies.agreeable)
        adapterB = await network.createNetworkEndpoint(
            config: .init(
                localPeerId: "twoPeer",
                localMetaData: nil,
                listeningNetwork: true,
                name: "B"
            )
        )
        await repoB.addNetworkAdapter(adapter: adapterB)

        let peersB = await repoB.peers()
        XCTAssertEqual(peersB, [])

        let connections = await network.connections()
        XCTAssertEqual(connections.count, 0)

        let endpoints = await network.endpoints
        XCTAssertEqual(endpoints.count, 2)
    }

    func testMostBasicRepoStartingPoints() async throws {
        // Repo
        //  property: peers [PeerId] - all (currently) connected peers
        let peersA = await repoA.peers()
        let peersB = await repoB.peers()
        XCTAssertEqual(peersA, [])
        XCTAssertEqual(peersA, peersB)

        let knownIdsA = await repoA.documentIds()
        XCTAssertEqual(knownIdsA, [])

        let knownIdsB = await repoA.documentIds()
        XCTAssertEqual(knownIdsB, knownIdsA)
    }

    func testCreateNetworkEndpoint() async throws {
        let foo = await network.createNetworkEndpoint(
            config: .init(
                localPeerId: "foo",
                localMetaData: nil,
                listeningNetwork: false,
                name: "Z"
            )
        )
        let endpoints = await network.endpoints
        XCTAssertEqual(endpoints.count, 3)
        let z = endpoints["Z"]
        XCTAssertNotNil(z)
    }

    func testConnect() async throws {
        for e in await network.endpoints {
            print(e)
        }
        try await adapterA.connect(to: "B")

        let connectionIdFromA = await adapterA._connections.first?.id
        let connectionIdFromB = await adapterB._connections.first?.id
        XCTAssertEqual(connectionIdFromA, connectionIdFromB)
        try print(XCTUnwrap(connectionIdFromA))
        await print("Adapter A", adapterA._connections[0].description)
        await print("Adapter B", adapterB._connections[0].description)

        await print("A: ", adapterA.peeredConnections) // missing
        await print("B: ", adapterB.peeredConnections)
    }

//    func testCreate() async throws {
//        let newDoc = try await repo.create()
//        XCTAssertNotNil(newDoc)
//        let knownIds = await repo.documentIds()
//        XCTAssertEqual(knownIds.count, 1)
//    }
//
//    func testFind() async throws {
//        let myId = DocumentId()
//        let handle = try await repo.create(id: myId)
//        XCTAssertEqual(myId, handle.id)
//
//        let foundDoc = try await repo.find(id: myId)
//        XCTAssertEqual(foundDoc.doc.actor, handle.doc.actor)
//    }
//
//    func testDelete() async throws {
//        let myId = DocumentId()
//        let _ = try await repo.create(id: myId)
//        var knownIds = await repo.documentIds()
//        XCTAssertEqual(knownIds.count, 1)
//
//        try await repo.delete(id: myId)
//        knownIds = await repo.documentIds()
//        XCTAssertEqual(knownIds.count, 0)
//
//        do {
//            let _ = try await repo.find(id: DocumentId())
//            XCTFail()
//        } catch {}
//    }
//
//    func testClone() async throws {
//        let myId = DocumentId()
//        let handle = try await repo.create(id: myId)
//        XCTAssertEqual(myId, handle.id)
//
//        let clonedHandle = try await repo.clone(id: myId)
//        XCTAssertNotEqual(handle.id, clonedHandle.id)
//        XCTAssertNotEqual(handle.doc.actor, clonedHandle.doc.actor)
//
//        let knownIds = await repo.documentIds()
//        XCTAssertEqual(knownIds.count, 2)
//    }

    // TBD:
    // - func storageIdForPeer(peerId) -> StorageId
    // - func subscribeToRemotes([StorageId])
}
