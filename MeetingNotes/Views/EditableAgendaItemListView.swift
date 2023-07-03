//
//  AgendaItemListView.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 7/1/23.
//

import Automerge
import SwiftUI

struct EditableAgendaItemListView: View {
    @ObservedObject var document: MeetingNotesDocument
    let agendaItemBinding: Binding<AgendaItem>
    @Environment(\.undoManager) var undoManager

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
            // registering an undo with even an empty handler for re-do marks
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
