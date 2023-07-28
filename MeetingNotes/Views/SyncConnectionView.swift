import Network
import SwiftUI

struct SyncConnectionView: View {
    @ObservedObject var syncConnection: SyncConnection

    func stateRepresentationView() -> some View {
        switch syncConnection.connectionState {
        case .setup:
            return Label {
                Text("")
            } icon: {
                Image(systemName: "arrow.up.circle").foregroundColor(.gray)
            }
        case let .waiting(nWError):
            return Label {
                Text("waiting: \(nWError.localizedDescription)")
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundColor(.yellow)
            }
        case .preparing:
            return Label {
                Text("")
            } icon: {
                Image(systemName: "arrow.up.circle").foregroundColor(.yellow)
            }
        case .ready:
            return Label {
                Text("")
            } icon: {
                Image(systemName: "arrow.up.circle").foregroundColor(.blue)
            }
        case let .failed(nWError):
            return Label {
                Text("waiting: \(nWError.localizedDescription)")
            } icon: {
                Image(systemName: "x.square").foregroundColor(.red)
            }
        case .cancelled:
            return Label {
                Text("")
            } icon: {
                Image(systemName: "x.square").foregroundColor(.gray)
            }
        default:
            return Label {
                Text("")
            } icon: {
                Image(systemName: "questionmark.square.dashed").foregroundColor(.primary)
            }
        }
    }

    var body: some View {
        HStack {
            if let txtRecord = syncConnection.endpoint?.txtRecord {
                Text(txtRecord[TXTRecordKeys.name] ?? "unknown")
            } else {
                Text(syncConnection.connectionId.uuidString)
            }
            Text(syncConnection.endpoint?.interface?.name ?? "")
            Spacer()
            stateRepresentationView()
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
