import Automerge
import SwiftUI

struct MeetingNoteDocumentView: View {
    @ObservedObject var document: MeetingNotesDocument
    @Environment(\.undoManager) var undoManager

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("Document ID: \(document.model.id)")
                    .font(.caption)
                Spacer()
            }
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
                Section("Attendees") {
                    ForEach(document.model.attendees, id: \.self) { attendee in
                        Text(attendee)
                    }
                }
                Section {
                    ForEach($document.model.agenda, id: \.self) { agendaItem in
                        EditableAgendaItemListView(document: document, agendaItemBinding: agendaItem)
                    }
                } header: {
                    HStack {
                        Text("Agenda")
                        Spacer()
                        Button {
                            let newAgendaItem = AgendaItem(title: "")
                            print("Adding agenda item!")
                            document.model.agenda.append(newAgendaItem)
                            try! document.storeModelUpdates()
                            undoManager?.registerUndo(withTarget: document) { _ in }
                            // registering an undo with even an empty handler for re-do marks
                            // the associated document as 'dirty' and causes SwiftUI to invoke
                            // a snapshot to save the file.
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                } footer: {
                    Text("footer here")
                }
            }
        }
    }
}

struct MeetingNoteDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        MeetingNoteDocumentView(document: MeetingNotesDocument.sample())
    }
}
