import Network
import SwiftUI

/// A view that shows nearby peers available for sync.
struct NWBrowserResultItemView: View {
    var documentId: DocumentId
    @ObservedObject var syncController: DocumentSyncCoordinator
    var result: NWBrowser.Result

    func nameFromResultMetadata() -> String {
        if case let .bonjour(txtrecord) = result.metadata {
            return txtrecord[TXTRecordKeys.name] ?? ""
        }
        return ""
    }

    func peerIdFromResultMetadata() -> String {
        if case let .bonjour(txtrecord) = result.metadata {
            return txtrecord[TXTRecordKeys.peer_id] ?? ""
        }
        return ""
    }

    var body: some View {
        VStack {
            HStack {
                Text(nameFromResultMetadata())
                Spacer()
                Button {
                    syncController.attemptToConnectToPeer(
                        result.endpoint,
                        forPeer: peerIdFromResultMetadata(),
                        withDoc: documentId
                    )
                } label: {
                    Text("Connect")
                }
            }
        }.font(.caption)
    }
}
