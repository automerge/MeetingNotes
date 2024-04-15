import AutomergeRepo
@preconcurrency import Combine
import Network
import SwiftUI

/// A view that shows the status of peers and network syncing.
@MainActor
struct PeerSyncView: View {
    var documentId: DocumentId

    @State var availablePeers: [AvailablePeer] = []
    @State var connectionList: [PeerConnection] = []
    @State var browserActive: Bool = false
    @State var browserStyling: Color = .primary

    @State private var nameToDisplay: String = ""
    @State private var editNamePopoverShown: Bool = false

    var body: some View {
        VStack {
            HStack {
                Text("Name: ")
                Button(action: {
                    editNamePopoverShown.toggle()
                }, label: {
                    Text("\(nameToDisplay)").font(.headline)
                })
                .buttonStyle(.borderless)
                .popover(isPresented: $editNamePopoverShown, content: {
                    Form {
                        Text("What name should we show for collaboration?")
                        TextField("identity", text: $nameToDisplay)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                // Require a name to continue
                                if !nameToDisplay.isEmpty {
                                    editNamePopoverShown.toggle()
                                }
                                Task {
                                    await peerToPeer.setName(nameToDisplay)
                                }
                            }
                        Button(role: .cancel) {
                            editNamePopoverShown.toggle()
                        } label: {
                            Text("OK")
                        }
                    }
                    .padding()
                })

                Spacer()
                Image(systemName: browserActive ? "bolt.horizontal.fill" : "bolt.horizontal")
                    .foregroundStyle(browserStyling)
            }
            .padding(.horizontal)
            if !availablePeers.isEmpty {
                Divider()
                HStack {
                    Text("Peers").bold()
                    Spacer()
                }
                .padding(.leading)
                LazyVStack {
                    ForEach(availablePeers, id: \.peerId) { result in
                        AvailablePeerView(result: result)
                            .padding(4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    }
                }
            }
            LazyVStack {
                ForEach(connectionList) { connection in
                    PeerConnectionView(peerConnection: connection)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.vertical)
        .onReceive(peerToPeer.connectionPublisher.receive(on: DispatchQueue.main), perform: { connectionList in
            self.connectionList = connectionList
        })
        .onReceive(peerToPeer.availablePeerPublisher.receive(on: DispatchQueue.main), perform: { availablePeerList in
            availablePeers = availablePeerList
        })
    }
}

struct PeerBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(iOS)
        NavigationView {
            MeetingNotesDocumentView(document: MeetingNotesDocument.sample())
        }
        #else
        MeetingNotesDocumentView(document: MeetingNotesDocument.sample())
        #endif
    }
}
