import SwiftUI

@main
struct MeetingNotesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MeetingNotesDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
