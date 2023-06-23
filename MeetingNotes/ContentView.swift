import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MeetingNotesDocument

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("Document ID: \(document.model.id)")
                    .font(.caption)
                Spacer()
            }
            Form {
                TextField("Title", text: $document.model.title)
            }
            TextEditor(text: $document.model.summary.value)
                .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: MeetingNotesDocument())
    }
}
