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
