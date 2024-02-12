//
//  WebSocketSyncIntegrationTests.swift
//  MeetingNotesTests
//
//  Created by Joseph Heck on 2/12/24.
//

import Automerge
import XCTest

final class WebSocketSyncIntegrationTests: XCTestCase {
    override func setUp() async throws {
        // setup
        // TODO: spin up and/or verify server to sync with is operational
    }

    override func tearDown() async throws {
        // teardown
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
        let websocket = WebsocketSyncConnection(nil, id: nil)
        websocket.registerDocument(document, id: documentId)
        let syncDestination = "ws://localhost:3030/"
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
            from: "ws://localhost:3030/"
        ) {
            let newAutomergeDoc = Document()
            let decoder = AutomergeDecoder(doc: newAutomergeDoc)
            let modelReplica = try decoder.decode(ExampleStruct.self)
            XCTAssertEqual(modelReplica, model)
        } else {
            XCTFail()
        }
    }
}
