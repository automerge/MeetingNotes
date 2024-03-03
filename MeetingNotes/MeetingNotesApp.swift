import SwiftUI
import AutomergeRepo

/// A shared instance of a document sync coordinator.
let sharedSyncCoordinator = DocumentSyncCoordinator.shared

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
}
