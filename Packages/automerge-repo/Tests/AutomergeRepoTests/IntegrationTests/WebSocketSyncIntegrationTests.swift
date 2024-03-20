//
//  WebSocketSyncIntegrationTests.swift
//  MeetingNotesTests
//
//  Created by Joseph Heck on 2/12/24.
//

import Automerge
import AutomergeRepo
import AutomergeUtilities
import OSLog
import XCTest

// NOTE(heckj): This integration test expects that you have a websocket server with the
// Automerge-repo sync protocol running at localhost:3030. If you're testing from the local
// repository, run the `./scripts/interop.sh` script to start up a local instance to
// respond.

final class WebSocketSyncIntegrationTests: XCTestCase {
    private static let subsystem = Bundle.main.bundleIdentifier!

    static let test = Logger(subsystem: subsystem, category: "WebSocketSyncIntegrationTests")
    let syncDestination = "ws://localhost:3030/"
//    let syncDestination = "wss://sync.automerge.org/"

    override func setUp() async throws {
        let isWebSocketConnectable = await webSocketAvailable(destination: syncDestination)
        try XCTSkipUnless(isWebSocketConnectable, "websocket unavailable for integration test")
    }

    override func tearDown() async throws {
        // teardown
    }

    func webSocketAvailable(destination: String) async -> Bool {
        guard let url = URL(string: destination) else {
            Self.test.error("invalid URL: \(destination, privacy: .public) - endpoint unavailable")
            return false
        }
        // establishes the websocket
        let request = URLRequest(url: url)
        let ws: URLSessionWebSocketTask = URLSession.shared.webSocketTask(with: request)
        ws.resume()
        Self.test.info("websocket to \(destination, privacy: .public) prepped, sending ping")
        do {
            try await ws.sendPing()
            Self.test.info("PING OK - returning true")
            ws.cancel(with: .normalClosure, reason: nil)
            return true
        } catch {
            Self.test.error("PING FAILED: \(error.localizedDescription, privacy: .public) - returning false")
            ws.cancel(with: .abnormalClosure, reason: nil)
            return false
        }
    }

    func testSync() async throws {
        // document structure for test
        struct ExampleStruct: Identifiable, Codable, Hashable {
            let id: UUID
            var title: String
            var discussion: AutomergeText

            init(title: String, discussion: String) {
                self.id = UUID()
                self.title = title
                self.discussion = AutomergeText(discussion)
            }
        }

        // initial setup and encoding of Automerge doc to sync it
        let document = Document()
        let documentId = DocumentId()
        let encoder = AutomergeEncoder(doc: document)
        let model = ExampleStruct(title: "new item", discussion: "editable text")
        try encoder.encode(model)

        // establish and sync the document
        // SwiftUI does it in a two-step: define and then add data through onAppear:
        let websocket = await WebsocketSyncConnection(nil, id: nil)
        await websocket.registerDocument(document, id: documentId)
        print("SYNCING DOCUMENT: \(documentId.description)")

        try await websocket.connect(syncDestination)
        try await websocket.runOngoingSync()

        // With the websocket protocol, we don't get confirmation of a sync being complete -
        // if the other side has everything and nothing new, they just won't send a response
        // back. In that case, we don't get any further responses - but we don't _know_ that
        // it's complete. In an initial sync there will always be at least one response, but
        // we can't quite count on this always being an initial sync... so I'm shimming in a
        // short "wait" here to leave the background tasks that receive WebSocket messages
        // running to catch any updates, and hoping that'll be enough time to complete it.
        try await Task.sleep(for: .seconds(5))
        await websocket.disconnect()

        // Spin up another websocket and try to get the document we just pushed into place
        print("REQUESTING DOCUMENT: \(documentId.description)")
        if let (copyOfDocument, _) = try await WebsocketSyncConnection.requestDocument(
            documentId,
            from: self.syncDestination
        ) {
            let decoder = AutomergeDecoder(doc: copyOfDocument)
            XCTAssertFalse(try copyOfDocument.isEmpty())
            // print(try copyOfDocument.schema().description)
            let modelReplica = try decoder.decode(ExampleStruct.self)
            XCTAssertEqual(modelReplica, model)
        } else {
            XCTFail()
        }
    }
}
