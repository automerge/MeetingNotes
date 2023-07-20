import Network
import SwiftUI

struct PeerSyncView: View {
    @ObservedObject var syncController: DocumentSyncController

    @State var browserActive: Bool = false
    @State var browserStyling: Color = .primary

    var body: some View {
        VStack {
            HStack {
                Text("Name: \(syncController.name)").font(.headline)
                Spacer()
                Image(systemName: browserActive ? "bolt.horizontal.fill" : "bolt.horizontal")
                    .foregroundStyle(browserStyling)
            }
            .padding(.horizontal)
            if !syncController.browserResults.isEmpty {
                Divider()
                HStack {
                    Text("Peers").bold()
                    Spacer()
                }
                .padding(.leading)
                LazyVStack {
                    ForEach(syncController.browserResults, id: \.hashValue) { result in
                        NWBrowserResultView(result: result)
                            .padding(4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.vertical)
        .onReceive(syncController.$browserState, perform: { status in
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
