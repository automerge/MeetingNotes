import SwiftUI

struct SyncView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var syncEnabled: Bool = false

    var body: some View {
        Button {
            syncEnabled.toggle()
        } label: {
            Image(
                systemName: syncEnabled ? "antenna.radiowaves.left.and.right.slash" :
                    "antenna.radiowaves.left.and.right"
            )
            .font(.title2)
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #endif
    }
}

struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        SyncView(document: MeetingNotesDocument.sample())
    }
}
