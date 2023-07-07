import SwiftUI

struct MergeView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var isImporting: Bool = false
    @State private var importURL: String = ""
    var body: some View {
        VStack {
            Button {
                isImporting = true
            } label: {
                Image(systemName: "tray.and.arrow.down").font(.largeTitle)
            }
            .padding()
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.meetingnote]
            ) { result in
                switch result {
                case let .success(success):
                    // url contains the URL of the chosen file.
                    importURL = success.absoluteString
                    
                    // gain access to the directory
                    if success.startAccessingSecurityScopedResource() {
                        defer { success.stopAccessingSecurityScopedResource() }
                        let filename = success.lastPathComponent
                        switch document.mergeFile(success) {
                        case .success(_):
                            print("MERGED \(filename)")
                        case let .failure(oops):
                            print(oops)
                        }
                        // access the directory URL
                        // (read templates in the directory, make a bookmark, etc.)
                        //onTemplatesDirectoryPicked(success)
                        // release access
                    }
                case let .failure(failure):
                    print(failure)
                }
            }

            Text(importURL)
            Spacer()
        }
    }
}

struct MergeView_Previews: PreviewProvider {
    static var previews: some View {
        MergeView(document: MeetingNotesDocument.sample())
    }
}
