import SwiftUI

/// A toolbar button for activating sync for a document.
struct WebSocketStatusView: View {
    @State private var syncEnabledIndicator: Bool = false
    var body: some View {
        Button {
            syncEnabledIndicator.toggle()
            if syncEnabledIndicator {
                sharedWebSocket.connect()
                sharedWebSocket.join(senderId: sharedSyncCoordinator.peerId.uuidString)
            } else {
                // sharedWebSocket.disconnect
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
}

/// Preview of the sync toolbar button.
struct WebSocketView_Previews: PreviewProvider {
    static var previews: some View {
        WebSocketStatusView()
    }
}
