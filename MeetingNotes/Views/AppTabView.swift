import SwiftUI

struct AppTabView: View {
    @ObservedObject var document: MeetingNotesDocument

    var body: some View {
        TabView {
            DocumentEditorView(document: document)
                .tabItem {
                    Label("Editor", systemImage: "doc.fill")
                }
            MergeView()
                .tabItem {
                    Label("Merge", systemImage: "doc.badge.gearshape.fill")
                }
            SyncView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
        }
    }
}

struct AppTabView_Previews: PreviewProvider {
    static var previews: some View {
        AppTabView(document: MeetingNotesDocument.sample())
    }
}
