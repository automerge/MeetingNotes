import AutomergeRepo
import Network
import SwiftUI

/// A view that shows nearby peers available for sync.
@MainActor
struct AvailablePeerView: View {
    let result: AvailablePeer

    var body: some View {
        VStack {
            HStack {
                Text(result.name)
                Spacer()
                Button {
                    Task {
                        try await peerToPeer.connect(to: result.endpoint)
                    }
                } label: {
                    Text("Connect")
                }
            }
        }.font(.caption)
    }
}
