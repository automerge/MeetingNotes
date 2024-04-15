import AutomergeRepo
import SwiftUI

public let repo = Repo(sharePolicy: SharePolicies.agreeable)
public let websocket = WebSocketProvider()
public let peerToPeer = PeerToPeerProvider(
    PeerToPeerProviderConfiguration(
        passcode: "AutomergeMeetingNotes",
        reconnectOnError: true,
        autoconnect: false
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
            await repo.addNetworkAdapter(adapter: websocket)
            await repo.addNetworkAdapter(adapter: peerToPeer)
        }
    }
}
