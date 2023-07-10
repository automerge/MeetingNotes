import Automerge
import SwiftUI

struct EditableAgendaItemView: View {
    // Document is needed within this file to link to the undo manager.
    @ObservedObject var document: MeetingNotesDocument
    // The undo manager triggers serializations and saving changes to the model
    // back into the automerge document (as a part of it's "save to disk"
    // sequence with ReferenceFileDocument.
    @Environment(\.undoManager) var undoManager

    let agendaItemBinding: Binding<AgendaItem>

    @State
    private var agendaTitle: String = ""
    @State
    private var agendaDetail: String = ""

    @State
    private var errorMsg: String = ""

    @FocusState
    private var titleIsFocused: Bool

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "note.text")
                TextField(text: $agendaTitle) {
                    Text("Enter a title for the agenda item.")
                }
                .padding(2)
                .border(.gray)
            }.padding(.horizontal)

            TextEditor(text: $agendaDetail)
                .padding(2)
                .border(Color.black)
                .padding()

            if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.callout)
                    .foregroundStyle(Color.red)
            }
        }
        .onAppear(perform: {
            agendaTitle = agendaItemBinding.title.wrappedValue
            agendaDetail = agendaItemBinding.discussion.value.wrappedValue
        })
        .focused($titleIsFocused)
        .onChange(of: agendaDetail, perform: { _ in
            agendaItemBinding.discussion.value.wrappedValue = agendaDetail
            do {
                try document.storeModelUpdates()
            } catch {
                errorMsg = error.localizedDescription
            }
            // Registering an undo with even an empty handler for re-do marks
            // the associated document as 'dirty' and causes SwiftUI to invoke
            // a snapshot to save the file.
            undoManager?.registerUndo(withTarget: document) { _ in }
        })
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
            // hides the extra space at the top of the view that comes
            // from the default navigation title.
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct EditableAgendaItemListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EditableAgendaItemView(
                document: MeetingNotesDocument.sample(),
                agendaItemBinding: .constant(AgendaItem(title: ""))
            )
        }
    }
}
