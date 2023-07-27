import Network
import SwiftUI

struct PeerSyncView: View {
    @ObservedObject var syncController: DocumentSyncController

    @State var browserActive: Bool = false
    @State var browserStyling: Color = .primary

    @State private var editNamePopoverShown: Bool = false
    @AppStorage(MeetingNotesDefaultKeys.sharingIdentity) private var sharingIdentity: String = MeetingNotesDocument
        .defaultSharingIdentity()
    
    var body: some View {
        VStack {
            HStack {
                Text("Name: ")
                Button(action: {
                    editNamePopoverShown.toggle()
                }, label: {
                    Text("\(syncController.name)").font(.headline)
                })
                .buttonStyle(.borderless)
                .popover(isPresented: $editNamePopoverShown, content: {
                    Form {
                        Text("What name should we show for collaboration?")
                        TextField("identity", text: $sharingIdentity)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                // Require a name to continue
                                if !sharingIdentity.isEmpty {
                                    editNamePopoverShown.toggle()
                                }
                                syncController.name = sharingIdentity
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
            if !syncController.browserResults.isEmpty {
                Divider()
                HStack {
                    Text("Peers").bold()
                    Spacer()
                }
                .padding(.leading)
                LazyVStack {
                    ForEach(syncController.browserResults, id: \.hashValue) { result in
                        NWBrowserResultItemView(syncController: syncController, result: result)
                            .padding(4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                    }
                }
            }
            if !syncController.outboundConnections.isEmpty {
                HStack {
                    Text("Outbound").bold()
                    Spacer()
                }
                LazyVStack {
                    ForEach(syncController.outboundConnectionKeys, id: \.self) { key in
                        HStack {
                            Text(key).font(.caption)
                            if let connection = syncController.outboundConnections[key]?.connection {
                                Text(connection.endpoint.debugDescription)
                                switch connection.state {
                                case .setup:
                                    Text("setup")
                                case .waiting(let nWError):
                                    Text("waiting: \(nWError.localizedDescription)")
                                case .preparing:
                                    Text("preparing")
                                case .ready:
                                    Text("ready")
                                case .failed(let nWError):
                                    Text("failed: \(nWError.localizedDescription)")
                                case .cancelled:
                                    Text("cancelled")
                                }
                            } else {
                                Text("nil")
                            }
                        }
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
