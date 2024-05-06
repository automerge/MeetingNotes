import AutomergeRepo
@preconcurrency import Combine
import Network
import OSLog
import SwiftUI

/// A view that shows the status of peers and network syncing.
@MainActor
struct PeerSyncView: View {
    var documentId: DocumentId

    @State var availablePeers: [AvailablePeer] = []
    @State var connectionList: [PeerConnectionInfo] = []
    @State var browserStyling: Color = .primary
    @State var browserState: NWBrowser.State = .setup
    @State var listenerState: NWListener.State = .setup

    @AppStorage(UserDefaultKeys.publicPeerName) var nameToDisplay: String = "???"
    @State private var editNamePopoverShown: Bool = false

    func browserColor() -> Color {
        switch browserState {
        case .setup:
            return .gray
        case .ready:
            return .blue
        case .failed:
            return .red
        case .cancelled:
            return .gray
        case .waiting:
            return .orange
        @unknown default:
            fatalError("unknown NWBrowser state: \(browserState)")
        }
    }

    func listenerColor() -> Color {
        switch listenerState {
        case .setup:
            return .gray
        case .waiting:
            return .orange
        case .ready:
            return .blue
        case .failed:
            return .red
        case .cancelled:
            return .orange
        @unknown default:
            fatalError("unknown NWBrowser state: \(browserState)")
        }
    }

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
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(browserColor())
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(listenerColor())
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
            // display all peers _except_ the one that represents ourself
            let reducedPeers = availablePeerList.filter { peer in
                peer.peerId != repo.peerId
            }
            availablePeers = reducedPeers
        })
        .onReceive(peerToPeer.browserStatePublisher.receive(on: DispatchQueue.main), perform: { state in
            Logger.document.debug("Browser state update to \(String(describing: state))")
            browserState = state
        })
        .onReceive(peerToPeer.listenerStatePublisher.receive(on: DispatchQueue.main), perform: { state in
            Logger.document.debug("Listener state update to \(String(describing: state))")
            listenerState = state
        })
        .task {
            // NOTE: this task gets invoked on _every_ re-appearance of the view - kind of the async
            // equivalent of .onAppear() {} closure structure.
            //
            // The result is this bit if repeatedly redundant, but covers the case where the app is
            // first coming online and a default "???" value should be set whatever the inline default
            // from the library can provide. Since this is an @AppStorage() setup, if there's a configured
            // setting, this won't get hit and we're just waiting cycles with the check.
            if nameToDisplay == "???" {
                // no user default is setup, so load a default value from the library
                nameToDisplay = await peerToPeer.peerName
            }
        }
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
