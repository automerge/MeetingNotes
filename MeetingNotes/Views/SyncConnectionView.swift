import Network
import SwiftUI

struct SyncConnectionView: View {
    @ObservedObject var syncConnection: SyncConnection

    func stateRepresentationView() -> some View {
        switch syncConnection.connectionState {
        case .setup:
            return Text("setup")
        case let .waiting(nWError):
            return Text("waiting: \(nWError.localizedDescription)")
        case .preparing:
            return Text("preparing")
        case .ready:
            return Text("ready")
        case let .failed(nWError):
            return Text("failed: \(nWError.localizedDescription)")
        case .cancelled:
            return Text("cancelled")
        default:
            return Text("?")
        }
    }

    var body: some View {
        HStack {
            Text(syncConnection.connectionId.uuidString).font(.caption)
            Text(syncConnection.endpoint?.debugDescription ?? "nil")
            Spacer()
            stateRepresentationView()
        }.font(.caption)
    }
}

// struct SyncConnectionView_Previews: PreviewProvider {
//    static var previews: some View {
//        SyncConnectionView()
//    }
// }
