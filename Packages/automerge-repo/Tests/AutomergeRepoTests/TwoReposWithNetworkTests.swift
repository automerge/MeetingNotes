import Automerge
@testable import AutomergeRepo
import AutomergeUtilities
import DistributedTracer
import Foundation
import Logging
import OTel
import OTLPGRPC
import RegexBuilder
import ServiceLifecycle
import Tracing
import XCTest

final class TwoReposWithNetworkTests: XCTestCase {
    let network = InMemoryNetwork.shared
    var repoOne: Repo!
    var repoTwo: Repo!

    var adapterOne: InMemoryNetworkEndpoint!
    var adapterTwo: InMemoryNetworkEndpoint!

    override func setUp() async throws {
        await TestTracer.shared.bootstrap(serviceName: "RepoTests")
        await withSpan("setUp") { _ in

            await withSpan("resetTestNetwork") { _ in
                await network.resetTestNetwork()
            }

            await withSpan("TwoReposWithNetworkTests_setup") { _ in

                let endpoints = await network.endpoints
                XCTAssertEqual(endpoints.count, 0)

                repoOne = Repo(sharePolicy: SharePolicies.readonly)
                // Repo setup WITHOUT any storage subsystem
                let storageId = await repoOne.storageId()
                XCTAssertNil(storageId)

                adapterOne = await network.createNetworkEndpoint(
                    config: .init(
                        listeningNetwork: false,
                        name: "One"
                    )
                )
                await repoOne.addNetworkAdapter(adapter: adapterOne)

                let peersOne = await repoOne.peers()
                XCTAssertEqual(peersOne, [])

                repoTwo = Repo(sharePolicy: SharePolicies.agreeable)
                adapterTwo = await network.createNetworkEndpoint(
                    config: .init(
                        listeningNetwork: true,
                        name: "Two"
                    )
                )
                await repoTwo.addNetworkAdapter(adapter: adapterTwo)

                let peersTwo = await repoTwo.peers()
                XCTAssertEqual(peersTwo, [])

                let connections = await network.connections()
                XCTAssertEqual(connections.count, 0)

                let endpointRecount = await network.endpoints
                XCTAssertEqual(endpointRecount.count, 2)
            }
        }
    }

    override func tearDown() async throws {
        if let tracer = await TestTracer.shared.tracer {
            tracer.forceFlush()
            // Testing does NOT have a polite shutdown waiting for a flush to complete, so
            // we explicitly give it some extra time here to flush out any spans remaining.
            try await Task.sleep(for: .seconds(1))
        }
    }

    func testMostBasicRepoStartingPoints() async throws {
        // Repo
        //  property: peers [PeerId] - all (currently) connected peers
        let peersOne = await repoOne.peers()
        let peersTwo = await repoTwo.peers()
        XCTAssertEqual(peersOne, [])
        XCTAssertEqual(peersOne, peersTwo)

        let knownIdsOne = await repoOne.documentIds()
        XCTAssertEqual(knownIdsOne, [])

        let knownIdsTwo = await repoOne.documentIds()
        XCTAssertEqual(knownIdsTwo, knownIdsOne)
    }

    func testCreateNetworkEndpoint() async throws {
        let _ = await network.createNetworkEndpoint(
            config: .init(
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
        // Enable the following line to see the messages from the connections
        // point of view:

        // await network.traceConnections(true)

        // Enable logging of received for the adapter:
        await adapterOne.logReceivedMessages(true)
        await adapterTwo.logReceivedMessages(true)
        // Logging doesn't show up in exported test output - it's interleaved into Xcode's console
        // which is useful for debugging tests

        try await withSpan("testConnect") { _ in
            try await adapterOne.connect(to: "Two")

            let connectionIdFromOne = await adapterOne._connections.first?.id
            let connectionIdFromTwo = await adapterTwo._connections.first?.id
            XCTAssertEqual(connectionIdFromOne, connectionIdFromTwo)

            let peersOne = await adapterOne.peeredConnections
            let peersTwo = await adapterTwo.peeredConnections
            XCTAssertFalse(peersOne.isEmpty)
            XCTAssertFalse(peersTwo.isEmpty)
        }
    }

    func testCreate() async throws {
        try await withSpan("testCreate") { _ in

            // initial conditions
            var knownOnTwo = await repoTwo.documentIds()
            var knownOnOne = await repoOne.documentIds()
            XCTAssertEqual(knownOnOne.count, 0)
            XCTAssertEqual(knownOnTwo.count, 0)

            // Create and add some doc content to the "server" repo - RepoTwo
            let newDocId = DocumentId()
            let newDoc = try await withSpan("repoTwo.create") { _ in
                try await repoTwo.create(id: newDocId)
            }
            // add some content to the new document
            try newDoc.doc.put(obj: .ROOT, key: "title", value: .String("INITIAL VALUE"))

            XCTAssertNotNil(newDoc)
            knownOnTwo = await repoTwo.documentIds()
            XCTAssertEqual(knownOnTwo.count, 1)
            XCTAssertEqual(knownOnTwo[0], newDocId)

            knownOnOne = await repoOne.documentIds()
            XCTAssertEqual(knownOnOne.count, 0)

            // "GO ONLINE"
            // await network.traceConnections(true)
            // await adapterTwo.logReceivedMessages(true)
            try await withSpan("adapterOne.connect") { _ in
                try await adapterOne.connect(to: "Two")
            }

            // verify that after sync, both repos have a copy of the document
            knownOnOne = await repoOne.documentIds()
            XCTAssertEqual(knownOnOne.count, 1)
            XCTAssertEqual(knownOnOne[0], newDocId)
        }
    }

    func testFind() async throws {
        // initial conditions
        var knownOnTwo = await repoTwo.documentIds()
        var knownOnOne = await repoOne.documentIds()
        XCTAssertEqual(knownOnOne.count, 0)
        XCTAssertEqual(knownOnTwo.count, 0)

        // "GO ONLINE"
        // await network.traceConnections(true)
        // await adapterTwo.logReceivedMessages(true)
        try await withSpan("adapterOne.connect") { _ in
            try await adapterOne.connect(to: "Two")
        }

        // Create and add some doc content to the "server" repo - RepoTwo
        let newDocId = DocumentId()
        let newDoc = try await withSpan("repoTwo.create") { _ in
            try await repoTwo.create(id: newDocId)
        }
        XCTAssertNotNil(newDoc.doc)
        // add some content to the new document
        try newDoc.doc.put(obj: .ROOT, key: "title", value: .String("INITIAL VALUE"))

        // Introducing a doc _after_ connecting shouldn't share it automatically
        knownOnTwo = await repoTwo.documentIds()
        XCTAssertEqual(knownOnTwo.count, 1)
        XCTAssertEqual(knownOnTwo[0], newDocId)

        knownOnOne = await repoOne.documentIds()
        XCTAssertEqual(knownOnOne.count, 0)

        // We can _request_ the document, and should find it
        do {
            let foundDoc = try await repoOne.find(id: newDocId)
            XCTAssertTrue(
                RepoHelpers.equalContents(doc1: foundDoc.doc, doc2: newDoc.doc)
            )
        } catch {
            let errMsg = error.localizedDescription
            print(errMsg)
        }
    }

    func testFindFail() async throws {
        // initial conditions
        var knownOnTwo = await repoTwo.documentIds()
        var knownOnOne = await repoOne.documentIds()
        XCTAssertEqual(knownOnOne.count, 0)
        XCTAssertEqual(knownOnTwo.count, 0)

        // Create and add some doc content to the "client" repo - RepoOne
        let newDocId = DocumentId()
        let newDoc = try await withSpan("repoTwo.create") { _ in
            try await repoOne.create(id: newDocId)
        }
        XCTAssertNotNil(newDoc.doc)
        // add some content to the new document
        try newDoc.doc.put(obj: .ROOT, key: "title", value: .String("INITIAL VALUE"))

        knownOnTwo = await repoTwo.documentIds()
        XCTAssertEqual(knownOnTwo.count, 0)

        knownOnOne = await repoOne.documentIds()
        XCTAssertEqual(knownOnOne.count, 1)
        XCTAssertEqual(knownOnOne[0], newDocId)
        // "GO ONLINE"
        await network.traceConnections(true)
        // await adapterTwo.logReceivedMessages(true)
        try await withSpan("adapterOne.connect") { _ in
            try await adapterOne.connect(to: "Two")
        }

        // Two doesn't automatically get the document because RepoOne
        // isn't configured to "share" automatically on connect
        // (it's not "agreeable")
        knownOnTwo = await repoTwo.documentIds()
        XCTAssertEqual(knownOnTwo.count, 0)

        knownOnOne = await repoOne.documentIds()
        XCTAssertEqual(knownOnOne.count, 1)

        // We can _request_ the document, but should be denied
        do {
            let _ = try await repoTwo.find(id: newDocId)
            XCTFail("RepoOne is private and should NOT share the document")
        } catch {
            let errMsg = error.localizedDescription
            print(errMsg)
        }
    }
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
