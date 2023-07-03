import SwiftUI
import Automerge

struct MeetingNoteDocumentView: View {
    @ObservedObject var document: MeetingNotesDocument

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
                    TextField("Title", text: $document.model.title)
                }
                Section("Attendees") {
                    ForEach(document.model.attendees, id: \.self) { attendee in
                        Text(attendee)
                    }
                }
                Section {
                    ForEach($document.model.agenda, id: \.self) { agendaItem in
                        TextField(text: agendaItem.title) {
                            Text(";-)")
                        }
                    }
                } header: {
                    HStack {
                        Text("Agenda")
                        Spacer()
                        Button {
                            let newAgendaItem = AgendaItem(title: "", discussion: Automerge.Text(""))
                            print("Adding agenda item!")
                            document.model.agenda.append(newAgendaItem)
                            try! document.storeModelUpdates()
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
