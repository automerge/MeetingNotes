import Automerge
import SwiftUI

struct EditableAgendaItemView: View {
    // Document is needed within this file to link to the undo manager.
    @ObservedObject var document: MeetingNotesDocument
    // The undo manager triggers serializations and saving changes to the model
    // back into the automerge document (as a part of it's "save to disk"
    // sequence with ReferenceFileDocument.
    @Environment(\.undoManager) var undoManager
    let agendaItemId: UUID?
    
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
            if let agendaItem = document.model.agendas.first(where: {
                   $0.id == agendaItemId
            }) {
                agendaTitle = agendaItem.title
                agendaDetail = agendaItem.discussion.value
            }
        })
        .focused($titleIsFocused)
        .onChange(of: agendaDetail, perform: { _ in
            updateAgendaItem()
        })
        .onChange(of: agendaTitle, perform: { _ in
            updateAgendaItem()
        })
        .autocorrectionDisabled()
        #if os(iOS)
            .textInputAutocapitalization(.never)
            // hides the extra space at the top of the view that comes
            // from the default navigation title.
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    private func updateAgendaItem() {
        var store = false
        if let indexPosition = document.model.agendas.firstIndex(where: {$0.id == agendaItemId}) {
            if document.model.agendas[indexPosition].title != agendaTitle {
                document.model.agendas[indexPosition].title = agendaTitle
                store = true
            }
            if document.model.agendas[indexPosition].discussion.value != agendaDetail {
                document.model.agendas[indexPosition].discussion.value = agendaDetail
                store = true
            }
            // Encode the model back into the Automerge document if the values changed.
            if store {
                do {
                    // serialize the changes into the internal Automerge document
                    try document.storeModelUpdates()
                } catch {
                    errorMsg = error.localizedDescription
                }
                // Registering an undo with even an empty handler for re-do marks
                // the associated document as 'dirty' and causes SwiftUI to invoke
                // a snapshot to save the file - on iOS.
                undoManager?.registerUndo(withTarget: document) { _ in }
            }
        }
    }
}

struct EditableAgendaItemListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EditableAgendaItemView(
                document: MeetingNotesDocument.sample(),
                agendaItemId: MeetingNotesDocument.sample().model.agendas[0].id
            )
        }
    }
}
