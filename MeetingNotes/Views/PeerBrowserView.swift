import Network
import SwiftUI

struct PeerBrowserView: View {
    var syncController: DocumentSyncController

    @State var browserActive: Bool = false
    @State var browserStyling: Color = .primary

    var body: some View {
        VStack {
            HStack {
                Image(systemName: browserActive ? "bolt.horizontal.fill" : "bolt.horizontal")
                    .foregroundStyle(browserStyling)
                Spacer()
            }
            .padding(.horizontal)
            if !syncController.browserResults.isEmpty {
                List(syncController.browserResults, id: \.hashValue) { result in
                    NWBrowserResultView(result: result)
                }
            }
        }
        .frame(maxHeight: 100)
        .padding(.vertical)
        .onReceive(syncController.$browserStatus, perform: { status in
            switch status {
            case .cancelled:
                browserActive = false
                browserStyling = .orange
            case .failed:
                browserActive = false
                browserStyling = .red
            case .ready:
                browserActive = true
                browserStyling = .green
            case .setup:
                browserActive = false
                browserStyling = .yellow
            case .waiting:
                browserActive = true
                browserStyling = .gray
            @unknown default:
                browserActive = false
                browserStyling = .gray
            }
        })
    }
}

struct PeerBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(iOS)
        NavigationView {
            AppTabView(document: MeetingNotesDocument.sample())
        }
        #else
        AppTabView(document: MeetingNotesDocument.sample())
        #endif
    }
}
