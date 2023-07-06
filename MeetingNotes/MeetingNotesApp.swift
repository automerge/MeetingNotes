import SwiftUI

/// The document-based Meeting Notes application.
@main
struct MeetingNotesApp: App {
    var body: some Scene {
        DocumentGroup {
            MeetingNotesDocument()
        } editor: { file in
            AppTabView(document: file.document)
        }
        .commands {
            CommandMenu("Merge") {
                Button("Merge in another document", action: {
                    // TODO: placeholder for finding and merging in an external document
                })
                .keyboardShortcut(KeyEquivalent("O"), modifiers: [.command, .shift])
            }
            CommandGroup(replacing: CommandGroupPlacement.saveItem) {
                // removes File > Close, Save As, Duplicate, Revert menu options
            }
            CommandGroup(replacing: CommandGroupPlacement.toolbar) {
                // removes show/hide toolbar, and customize toolbar menu options
            }
        }
    }
}
