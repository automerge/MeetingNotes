import SwiftUI

/// A toolbar button for activating sync for a document.
struct SyncView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var syncEnabledIndicator: Bool = false
    var body: some View {
        Button {
            syncEnabledIndicator.toggle()
            if syncEnabledIndicator {
                // only enable listening if an identity has been chosen
                sharedSyncCoordinator.activate()
            } else {
                sharedSyncCoordinator.deactivate()
            }
        } label: {
            Image(
                systemName: syncEnabledIndicator ? "antenna.radiowaves.left.and.right.slash" :
                    "antenna.radiowaves.left.and.right"
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
        SyncView(document: MeetingNotesDocument.sample())
    }
}
