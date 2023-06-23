import SwiftUI

@main
struct MeetingNotesApp: App {
    var body: some Scene {
        DocumentGroup {
            MeetingNotesDocument()
        } editor: { file in
            ContentView(document: file.document)
        }
    }
}
