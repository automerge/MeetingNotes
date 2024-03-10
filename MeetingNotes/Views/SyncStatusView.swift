import AutomergeRepo
import SwiftUI

/// A toolbar button for activating sync for a document.
@MainActor
struct SyncStatusView: View {
    @State private var syncEnabledIndicator: Bool = false
    var body: some View {
        Button {
            syncEnabledIndicator.toggle()
            if syncEnabledIndicator {
                // only enable listening if an identity has been chosen
                DocumentSyncCoordinator.shared.activate()
            } else {
                DocumentSyncCoordinator.shared.deactivate()
            }
        } label: {
            Image(
                systemName: syncEnabledIndicator ? "antenna.radiowaves.left.and.right" :
                    "antenna.radiowaves.left.and.right.slash"
            )
            .font(.title2)
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #endif
    }
}

/// Preview of the sync toolbar button.
struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        SyncStatusView()
    }
}
