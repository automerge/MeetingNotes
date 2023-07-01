import SwiftUI

/// The document-based Meeting Notes application.
@main
struct MeetingNotesApp: App {
    var body: some Scene {
        DocumentGroup {
            MeetingNotesDocument()
        } editor: { file in
            MeetingNoteDocumentView(document: file.document)
        }
    }
}
