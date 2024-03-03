import Network
import SwiftUI
import AutomergeRepo

/// A view that displays a sync connection and its state.
struct SyncConnectionView: View {
    @ObservedObject var syncConnection: SyncConnection

    func stateRepresentationView() -> some View {
        switch syncConnection.connectionState {
        case .setup:
            return Image(systemName: "arrow.up.circle").foregroundColor(.gray)
        case .waiting:
            return Image(systemName: "exclamationmark.triangle").foregroundColor(.yellow)
        case .preparing:
            return Image(systemName: "arrow.up.circle").foregroundColor(.yellow)
        case .ready:
            return Image(systemName: "arrow.up.circle").foregroundColor(.blue)
        case .failed:
            return Image(systemName: "x.square").foregroundColor(.red)
        case .cancelled:
            return Image(systemName: "x.square").foregroundColor(.gray)
        default:
            return Image(systemName: "questionmark.square.dashed").foregroundColor(.primary)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            stateRepresentationView()
            if let txtRecord = syncConnection.endpoint?.txtRecord {
                Text(txtRecord[TXTRecordKeys.name] ?? "unknown")
            } else {
                Text(syncConnection.shortId)
            }
            Text(syncConnection.endpoint?.interface?.name ?? "")
            Spacer()
            Button {
                syncConnection.cancel()
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
//        SyncConnectionView()
//    }
// }
