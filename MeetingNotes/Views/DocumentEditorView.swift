import Automerge
import SwiftUI

struct DocumentEditorView: View {
    // Document is needed within this file to link to the undo manager.
    @ObservedObject var document: MeetingNotesDocument
    // The undo manager triggers serializations and saving changes to the model
    // back into the automerge document (as a part of it's "save to disk"
    // sequence with ReferenceFileDocument.
    @Environment(\.undoManager) var undoManager

    var body: some View {
        List {
            Section {
                TextField("Meeting Title", text: $document.model.title)
                    .onSubmit {
                        undoManager?.registerUndo(withTarget: document) { _ in }
                        // registering an undo with even an empty handler for re-do marks
                        // the associated document as 'dirty' and causes SwiftUI to invoke
                        // a snapshot to save the file.
                    }
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            }
            Section {
                ForEach($document.model.agendas) { $agendaItem in
                    NavigationLink {
                        EditableAgendaItemView(document: document, agendaItemBinding: $agendaItem)
                    } label: {
                        Label(agendaItem.title, systemImage: "note.text")
                    }
                }
            } header: {
                HStack {
                    Text("Agenda")
                    Button {
                        let newAgendaItem = AgendaItem(title: "")
                        print("Adding agenda item!")
                        document.model.agendas.append(newAgendaItem)
                        undoManager?.registerUndo(withTarget: document) { _ in }
                        // Registering an undo with even an empty handler for re-do marks
                        // the associated document as 'dirty' and causes SwiftUI to invoke
                        // a snapshot to save the file.
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            Section {
                HStack {
                    Spacer()
                    Text("\(document.id)")
                        .font(.caption)
                    Spacer()
                }
            } header: {
                Text("Document Id")
            }
        }
    }
}

struct DocumentEditorView_Previews: PreviewProvider {
    static var previews: some View {
        DocumentEditorView(document: MeetingNotesDocument.sample())
    }
}
