import Automerge
@testable import AutomergeRepo
import AutomergeUtilities
import Logging
import OTel
import OTLPGRPC
import Tracing
import XCTest

final class TwoReposWithNetworkTests: XCTestCase {
    let network = InMemoryNetwork.shared
    var repoOne: Repo!
    var repoTwo: Repo!

    var tracer: OTelTracer<
        OTelRandomIDGenerator<SystemRandomNumberGenerator>,
        OTelConstantSampler,
        OTelW3CPropagator,
        OTelBatchSpanProcessor<OTLPGRPCSpanExporter, ContinuousClock>,
        ContinuousClock
    >? = nil

    var adapterOne: InMemoryNetworkEndpoint!
    var adapterTwo: InMemoryNetworkEndpoint!

    override func setUp() async throws {
        let environment = OTelEnvironment.detected()
        let resourceDetection = OTelResourceDetection(detectors: [
            OTelProcessResourceDetector(),
            OTelEnvironmentResourceDetector(environment: environment),
            .manual(OTelResource(attributes: ["service.name": "TwoRepoTest"])),
        ])

        let resource: OTelResource = await resourceDetection.resource(environment: environment, logLevel: .trace)

        /*
         Bootstrap the logging system to use the OTel metadata provider.
         This will automatically include trace and span IDs in log statements
         from your app and its dependencies.
         */
        LoggingSystem.bootstrap({ label, _ in
            var handler = StreamLogHandler.standardOutput(label: label)
            // We set the lowest possible minimum log level to see all log statements.
            handler.logLevel = .trace
            return handler
        }, metadataProvider: .otel)

        let logger = Logger(label: "example")
        logger.debug("TEST MARKER")

        // Here we create an OTel span exporter that sends spans via gRPC to an OTel collector.
        let exporter = try OTLPGRPCSpanExporter(configuration: .init(environment: environment))
        /*
         This exporter is passed to a batch span processor.
         The processor receives ended spans from the tracer, batches them up, and finally forwards them to the exporter.
         */
        let processor = OTelBatchSpanProcessor(exporter: exporter, configuration: .init(environment: environment))
        /*
         We need to await tracer initialization since the tracer needs
         some time to detect attributes about the resource being traced.
         */
        let myTracer = OTelTracer(
            idGenerator: OTelRandomIDGenerator(),
            sampler: OTelConstantSampler(isOn: true),
            propagator: OTelW3CPropagator(),
            processor: processor,
            environment: environment,
            resource: resource
        )
        /*
         Once we have a tracer, we bootstrap the instrumentation system to use it.
         This configures your application code and any of your dependencies to use the OTel tracer.
         */
        InstrumentationSystem.bootstrap(myTracer)
        Task {
            try await myTracer.run()
        }
        tracer = myTracer

        await withSpan("resetTestNetwork") { _ in
            await network.resetTestNetwork()
        }

        await withSpan("TwoReposWithNetworkTests_setup") { _ in

            let endpoints = await network.endpoints
            XCTAssertEqual(endpoints.count, 0)

            repoOne = Repo(sharePolicy: SharePolicies.agreeable)
            let repoOneMetaData = await repoOne.localPeerMetadata
            // Repo setup WITHOUT any storage subsystem
            let storageId = await repoOne.storageId()
            XCTAssertNil(storageId)

            adapterOne = await network.createNetworkEndpoint(
                config: .init(
                    localPeerId: "onePeerId",
                    localMetaData: repoOneMetaData,
                    listeningNetwork: false,
                    name: "One"
                )
            )
            await repoOne.addNetworkAdapter(adapter: adapterOne)

            let peersOne = await repoOne.peers()
            XCTAssertEqual(peersOne, [])

            repoTwo = Repo(sharePolicy: SharePolicies.agreeable)
            let repoTwoMetaData = await repoTwo.localPeerMetadata
            adapterTwo = await network.createNetworkEndpoint(
                config: .init(
                    localPeerId: "twoPeerId",
                    localMetaData: repoTwoMetaData,
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

    override func tearDown() async throws {
        if let tracer {
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
            let newDocId = DocumentId()
            let newDoc = try await withSpan("repoOne.create") { _ in
                try await repoOne.create(id: newDocId)
            }

            XCTAssertNotNil(newDoc)
            let knownIds = await repoOne.documentIds()
            XCTAssertEqual(knownIds.count, 1)
            XCTAssertEqual(knownIds[0], newDocId)

            // "GO ONLINE"
            await network.traceConnections(true)

            await adapterTwo.logReceivedMessages(true)
            try await withSpan("adapterOne.connect") { _ in
                try await adapterOne.connect(to: "Two")
            }
            #warning("Initiating sync, but not getting a response over my 'test' network")
        }
    }

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
