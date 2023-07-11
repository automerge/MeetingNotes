import SwiftUI

struct AppTabView: View {
    @ObservedObject var document: MeetingNotesDocument
    // The undo manager triggers serializations and saving changes to the model
    // back into the automerge document (as a part of it's "save to disk"
    // sequence with ReferenceFileDocument.
    @Environment(\.undoManager) var undoManager
    @State private var selection: UUID?

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            VStack {
                TextField("Meeting Title", text: $document.model.title)
                    .onSubmit {
                        undoManager?.registerUndo(withTarget: document) { _ in }
                        // registering an undo with even an empty handler for re-do marks
                        // the associated document as 'dirty' and causes SwiftUI to invoke
                        // a snapshot to save the file.
                    }
                    .autocorrectionDisabled()
                List($document.model.agendas, selection: $selection) {
                    $agendaItem in
                    NavigationLink {
                        EditableAgendaItemView(document: document, agendaItemBinding: $agendaItem)
                    } label: {
                        Label(agendaItem.title, systemImage: "note.text")
                    }
                }
//                } header: {
//                    HStack {
//                        Text("Agenda")
//                        Button {
//                            let newAgendaItem = AgendaItem(title: "")
//                            print("Adding agenda item!")
//                            document.model.agendas.append(newAgendaItem)
//                            undoManager?.registerUndo(withTarget: document) { _ in }
//                            // Registering an undo with even an empty handler for re-do marks
//                            // the associated document as 'dirty' and causes SwiftUI to invoke
//                            // a snapshot to save the file.
//                        } label: {
//                            Image(systemName: "plus.circle")
//                        }
//                        .buttonStyle(.plain)
//                        Spacer()
//                    }
            }
//                Section {
//                    HStack {
//                        Spacer()
//                        Text("\(document.id)")
//                            .font(.caption)
//                        Spacer()
//                    }
//                } header: {
//                    Text("Document Id")
//                }
//            }
            .navigationSplitViewColumnWidth(250)
        } detail: {
            if let itemId = selection,
               let itemBinding = $document.model.agendas.first(where: {
                   $0.wrappedValue.id == itemId
               })
            {
                EditableAgendaItemView(document: document, agendaItemBinding: itemBinding)
            } else {
                Text("Select an agenda item")
            }
        }
        #else // iOS
        DocumentEditorView(document: document)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Sync") {}
                    MergeView(document: document)
                }
            }
        #endif
    }
}

struct AppTabView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(iOS)
        NavigationView {
            AppTabView(document: MeetingNotesDocument.sample())
        }
        #else
        AppTabView(document: MeetingNotesDocument.sample())
        #endif
    }
}
