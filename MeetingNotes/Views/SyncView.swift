import SwiftUI

struct SyncView: View {
    @ObservedObject var document: MeetingNotesDocument

    @AppStorage(MeetingNotesDefaultKeys.sharingIdentity) private var sharingIdentity: String = MeetingNotesDocument
        .defaultSharingIdentity()
    @State private var syncEnabledIndicator: Bool = false
    @State private var sheetShown: Bool = false
    var body: some View {
        Button {
            if !syncEnabledIndicator {
                // Activate the sheet to collect a passcode only on activating sync.
                sheetShown.toggle()
            }
            syncEnabledIndicator.toggle()
            if syncEnabledIndicator {
                // only enable listening if an identity has been chosen
                document.syncController.activate()
            } else {
                document.syncController.deactivate()
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
        // FIXME: move all this sheet stuff to a pop-over in NSBrowserResultView on the sharing name
        .sheet(isPresented: $sheetShown) {
            if !sharingIdentity.isEmpty {
                UserDefaults.standard.setValue(sharingIdentity, forKey: MeetingNotesDefaultKeys.sharingIdentity)
                document.syncController.name = sharingIdentity
            }
        } content: {
            Form {
                Text("What name should we show for collaboration?")
                TextField("identity", text: $sharingIdentity)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        // Require a name to continue
                        if !sharingIdentity.isEmpty {
                            sheetShown.toggle()
                        }
                    }
                Button(role: .cancel) {
                    sheetShown.toggle()
                } label: {
                    Text("OK")
                }
            }
            .padding()
            .presentationDetents([.medium])
        }
    }
}

struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        SyncView(document: MeetingNotesDocument.sample())
    }
}
