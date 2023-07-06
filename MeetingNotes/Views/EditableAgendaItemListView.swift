import Automerge
import SwiftUI

struct EditableAgendaItemListView: View {
    // Document is needed within this file to link to the undo manager.
    @ObservedObject var document: MeetingNotesDocument
    // The undo manager triggers serializations and saving changes to the model
    // back into the automerge document (as a part of it's "save to disk"
    // sequence with ReferenceFileDocument.
    @Environment(\.undoManager) var undoManager

    let agendaItemBinding: Binding<AgendaItem>

    @State
    private var agendaTitle: String = ""
    @FocusState
    private var titleIsFocused: Bool

    var body: some View {
        VStack {
            TextField(text: $agendaTitle) {
                Text("Enter a title for the agenda item.")
            }
        }.onAppear(perform: {
            agendaTitle = agendaItemBinding.title.wrappedValue
        })
        .focused($titleIsFocused)
        .onSubmit {
            agendaItemBinding.title.wrappedValue = agendaTitle
            // Registering an undo with even an empty handler for re-do marks
            // the associated document as 'dirty' and causes SwiftUI to invoke
            // a snapshot to save the file.
            undoManager?.registerUndo(withTarget: document) { _ in }
        }
        .autocorrectionDisabled()
        #if os(iOS)
            .textInputAutocapitalization(.never)
        #endif
    }
}

struct EditableAgendaItemListView_Previews: PreviewProvider {
    static var previews: some View {
        EditableAgendaItemListView(
            document: MeetingNotesDocument.sample(),
            agendaItemBinding: .constant(AgendaItem(title: ""))
        )
    }
}
