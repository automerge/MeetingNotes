import AutomergeRepo
import SwiftUI

/// A toolbar button for activating sync for a document.
@MainActor
struct WebSocketStatusView: View {
    enum SyncTargets: String, Sendable, CaseIterable, Identifiable {
        case local
        case automerge
        // Identifiable conformance
        var id: Self { self }
        // URL string assist
        var url: URL {
            switch self {
            case .local:
                return URL(string: "ws://localhost:3030/")!
            case .automerge:
                return URL(string: "wss://sync.automerge.org/")!
            }
        }
    }

    @ObservedObject var document: MeetingNotesDocument
    @State private var syncEnabledIndicator: Bool = false
    @State private var syncDestination: SyncTargets = .automerge

    var body: some View {
        HStack {
//            Picker("Destination", selection: $syncDestination) {
//                ForEach(SyncTargets.allCases) { dest in
//                    Text(dest.rawValue.capitalized)
//                }
//            }
//            .pickerStyle(.segmented)
//            .disabled(syncEnabledIndicator)

            Button {
                syncEnabledIndicator.toggle()
                if syncEnabledIndicator {
                    Task {
                        try await websocket.connect(to: syncDestination.url)
                    }
                } else {
                    Task {
                        await websocket.disconnect()
                    }
                }
            } label: {
                Image(
                    systemName: syncEnabledIndicator ? "wifi" :
                        "wifi.slash"
                )
                .font(.title2)
            }
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
        }
    }
}

/// Preview of the sync toolbar button.
struct WebSocketView_Previews: PreviewProvider {
    static var previews: some View {
        WebSocketStatusView(document: MeetingNotesDocument.sample())
    }
}
