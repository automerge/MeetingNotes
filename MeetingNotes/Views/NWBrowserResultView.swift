import Network
import SwiftUI

struct NWBrowserResultView: View {
    var result: NWBrowser.Result
    var body: some View {
        HStack {
            Text(result.endpoint.debugDescription)
            Text(result.interfaces.debugDescription)
            Text(result.metadata.debugDescription)
        }
    }
}
