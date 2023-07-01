import SwiftUI

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
                Section("Agenda") {
                    ForEach(document.model.agenda, id: \.self) { agendaItem in
                        Text(agendaItem.title)
                    }
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
