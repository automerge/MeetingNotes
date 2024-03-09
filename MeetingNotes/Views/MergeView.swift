import OSLog
import SwiftUI

/// A toolbar button to coordinate merging documents.
@MainActor
struct MergeView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var isImporting: Bool = false
    @State private var importURL: String = ""
    var body: some View {
        Button {
            isImporting = true
        } label: {
            Image(systemName: "tray.and.arrow.down")
                .font(.title2)
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #endif
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
                    case .success:
                        Logger.document.info("Merged external file \(filename, privacy: .public)")
                    case let .failure(mergeError):
                        Logger.document
                            .error(
                                "Error attempting to merge file: \(mergeError.localizedDescription, privacy: .public)"
                            )
                    }
                }
            case let .failure(failure):
                print(failure)
            }
        }
    }
}

/// Preview of the merge toolbar button.
struct MergeView_Previews: PreviewProvider {
    static var previews: some View {
        MergeView(document: MeetingNotesDocument.sample())
    }
}
