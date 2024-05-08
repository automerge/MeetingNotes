import AutomergeRepo
import SwiftUI

/// A global repository for storing and synchronizing Automerge documents by ID.
let repo = Repo(sharePolicy: SharePolicy.agreeable)
/// A WebSocket network provider for the repository.
let websocket = WebSocketProvider(.init(reconnectOnError: true, loggingAt: .tracing))
/// A peer-to-peer network provider for the repository.
let peerToPeer = PeerToPeerProvider(
    PeerToPeerProviderConfiguration(
        passcode: "AutomergeMeetingNotes",
        reconnectOnError: true,
        autoconnect: false,
        logVerbosity: .tracing
    )
)

/// The document-based Meeting Notes application.
@main
struct MeetingNotesApp: App {
    var body: some Scene {
        DocumentGroup {
            MeetingNotesDocument()
        } editor: { file in
            MeetingNotesDocumentView(document: file.document)
        }
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.toolbar) {
                // removes show/hide toolbar, and customize toolbar menu options
            }
        }
    }

    init() {
        Task {
            // Enable repo tracing
            await repo.setLogLevel(.network, to: .tracing)
            await repo.setLogLevel(.resolver, to: .tracing)
            await repo.setLogLevel(.repo, to: .tracing)
            // Enable network adapters
            await repo.addNetworkAdapter(adapter: websocket)
            await repo.addNetworkAdapter(adapter: peerToPeer)
        }
    }
}
