import AutomergeRepo
import Network
import SwiftUI

/// A view that displays a sync connection and its state.
@MainActor
struct PeerConnectionView: View {
    let peerConnection: PeerConnection

    func stateRepresentationView() -> some View {
        if peerConnection.peered {
            if peerConnection.initiated {
                return Image(systemName: "arrow.up.circle").foregroundColor(.blue)
            } else {
                return Image(systemName: "arrow.down.circle").foregroundColor(.blue)
            }
        } else {
            return Image(systemName: "questionmark.square.dashed").foregroundColor(.primary)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            stateRepresentationView()
            Text("\(peerConnection.peerId) at \(peerConnection.endpoint)")
            Spacer()
            Button {
                Task {
                    await peerToPeer.disconnect(peerId: peerConnection.peerId)
                }
            } label: {
                Image(systemName: "xmark.square")
            }
        }
        .font(.caption)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}

// struct SyncConnectionView_Previews: PreviewProvider {
//    static var previews: some View {
//        PeerConnectionView()
//    }
// }
