import Network
import SwiftUI

struct NWBrowserResultView: View {
    var result: NWBrowser.Result

    func idFromResultMetadata() -> String {
        if case let .bonjour(txtrecord) = result.metadata {
            return txtrecord["id"] ?? ""
        }
        return ""
    }

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
            }
            HStack {
                Text(idFromResultMetadata())
                Spacer()
            }
        }.font(.caption)
    }
}
