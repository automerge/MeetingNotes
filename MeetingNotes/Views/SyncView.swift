import SwiftUI

struct SyncView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var sharingPasscode: String = ""
    @State private var syncEnabledIndicator: Bool = false
    @State private var sheetShown: Bool = false
    var body: some View {
        Button {
            if !syncEnabledIndicator {
                // Activate the sheet to collect a passcode only on activating sync.
                sheetShown.toggle()
            }
            syncEnabledIndicator.toggle()
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
        .sheet(isPresented: $sheetShown) {
            // If there isn't a sharing passcode set when the sheet
            // is dismissed, disable the sync enabled indicator.
            if sharingPasscode.isEmpty {
                syncEnabledIndicator = false
            }
        } content: {
            VStack {
                Text("Provide a passcode to allow collaboration")
                TextField("passcode", text: $sharingPasscode)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onSubmit {
                        // Require a passcode to continue
                        if !sharingPasscode.isEmpty {
                            sheetShown.toggle()
                        }
                    }
                Button(role: .cancel) {
                    sheetShown.toggle()
                } label: {
                    Text("Dismiss")
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
