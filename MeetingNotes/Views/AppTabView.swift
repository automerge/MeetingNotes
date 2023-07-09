import SwiftUI

struct AppTabView: View {
    @ObservedObject var document: MeetingNotesDocument

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            TabView {
                DocumentEditorView(document: document)
                    .tabItem {
                        Label("Editor", systemImage: "doc.fill")
                    }
                MergeView(document: document)
                    .tabItem {
                        Label("Merge", systemImage: "doc.badge.gearshape.fill")
                    }
                SyncView()
                    .tabItem {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    }
            }
            .navigationSplitViewColumnWidth(250)
        } detail: {}
        #else // iOS
        TabView {
            DocumentEditorView(document: document)
                .tabItem {
                    Label("Editor", systemImage: "doc.fill")
                }
            MergeView(document: document)
                .tabItem {
                    Label("Merge", systemImage: "doc.badge.gearshape.fill")
                }
            SyncView()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
        }
        #endif
    }
}

struct AppTabView_Previews: PreviewProvider {
    static var previews: some View {
        AppTabView(document: MeetingNotesDocument.sample())
    }
}
