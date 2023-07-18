import Network
import SwiftUI

struct PeerBrowserView: View {
    @EnvironmentObject var peerBrowser: PeerBrowser

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
            if !peerBrowser.browserResults.isEmpty {
                List(peerBrowser.browserResults, id: \.hashValue) { result in
                    NWBrowserResultView(result: result)
                }
            }
        }
        .frame(maxHeight: 100)
        .padding(.vertical)
        .onReceive(peerBrowser.$browserStatus, perform: { status in
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
        .environmentObject(PeerBrowser())
        #else
        AppTabView(document: MeetingNotesDocument.sample())
            .environmentObject(PeerBrowser())
        #endif
    }
}
