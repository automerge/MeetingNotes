import SwiftUI

/// A toolbar button for activating sync for a document.
struct WebSocketStatusView: View {
    enum SyncTargets: String, CaseIterable, Identifiable {
        case local
        case automerge
        // Identifiable conformance
        var id: Self { self }
        // URL string assist
        var urlString: String {
            switch self {
            case .local:
                return "ws://localhost:3030/"
            case .automerge:
                return "wss://sync.automerge.org/"
            }
        }
    }

    @ObservedObject var document: MeetingNotesDocument
    @StateObject private var websocket = WebsocketSyncConnection()
    @State private var syncEnabledIndicator: Bool = false
    @State private var syncDestination: SyncTargets = .local

    var body: some View {
        HStack {
            Picker("Destination", selection: $syncDestination) {
                ForEach(SyncTargets.allCases) { dest in
                    Text(dest.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .disabled(syncEnabledIndicator)

            Button {
                syncEnabledIndicator.toggle()
                if syncEnabledIndicator {
                    Task {
                        await websocket.connect(syncDestination.urlString)
                    }
                } else {
                    Task {
                        await websocket.disconnect()
                    }
                }
            } label: {
                Image(
                    systemName: syncEnabledIndicator ? "wifi.slash" :
                        "wifi"
                )
                .font(.title2)
            }
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
        }
        .onAppear {
            websocket.registerDocument(document.doc, id: document.id)
        }
    }
}

/// Preview of the sync toolbar button.
struct WebSocketView_Previews: PreviewProvider {
    static var previews: some View {
        WebSocketStatusView(document: MeetingNotesDocument.sample())
    }
}
