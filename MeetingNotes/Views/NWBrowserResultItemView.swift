import Network
import SwiftUI

struct NWBrowserResultItemView: View {
    @ObservedObject var syncController: DocumentSyncController
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
                    syncController.attemptToConnectToPeer(result.endpoint, forPeer: peerIdFromResultMetadata())
                } label: {
                    Image(systemName: "bolt.horizontal.fill")
                }
            }
        }.font(.caption)
    }
}
