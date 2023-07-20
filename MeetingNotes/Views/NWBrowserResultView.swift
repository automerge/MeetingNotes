import Network
import SwiftUI

struct NWBrowserResultView: View {
    var result: NWBrowser.Result
    var connection: NWConnection?

    func nameFromResultMetadata() -> String {
        if case let .bonjour(txtrecord) = result.metadata {
            return txtrecord["name"] ?? ""
        }
        return ""
    }

    var body: some View {
        VStack {
            HStack {
                Text(nameFromResultMetadata())
                Spacer()
                Image(systemName: connection != nil ? "bolt.horizontal.fill" : "bolt.horizontal")
            }
        }.font(.caption)
    }
}
