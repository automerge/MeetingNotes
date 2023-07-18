import SwiftUI

struct SyncView: View {
    @ObservedObject var document: MeetingNotesDocument

    @State private var sharingPasscode: String = ""
    @State private var syncEnabled: Bool = false
    @State private var sheetShown: Bool = false
    var body: some View {
        Button {
            if !syncEnabled {
                // Activate the sheet to collect a passcode only on activating sync.
                sheetShown.toggle()
            }
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
        .sheet(isPresented: $sheetShown) {
            VStack {
                Text("Provide a passcode to allow collaboration")
                TextField("passcode", text: $sharingPasscode)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onSubmit {
                        sheetShown.toggle()
                    }
            }.padding()
        }
    }
}

struct SyncView_Previews: PreviewProvider {
    static var previews: some View {
        SyncView(document: MeetingNotesDocument.sample())
    }
}
