import OSLog
import SwiftUI

struct AppTabView: View {
    @ObservedObject var document: MeetingNotesDocument
    // The undo manager triggers serializations and saving changes to the model
    // back into the automerge document (as a part of it's "save to disk"
    // sequence with ReferenceFileDocument.
    @Environment(\.undoManager) var undoManager
    @State private var selection: AgendaItem.ID?

    var body: some View {
        NavigationSplitView {
            VStack {
                TextField("Meeting Title", text: $document.model.title)
                    // Normally, I'd likely make this `.onSubmit`, but with
                    // onChange, I can see live sync effects on each character update
                    // in the text field.
                    .onChange(of: document.model.title, perform: { _ in
                        undoManager?.registerUndo(withTarget: document) { _ in }
                        // Registering an undo with even an empty handler for re-do marks
                        // the associated document as 'dirty' and causes SwiftUI to invoke
                        // a snapshot to save the file.
                        updateDoc()
                    })
                    .autocorrectionDisabled()
                    .padding(.horizontal)
                HStack {
                    Spacer()
                    Button {
                        document.model.agendas.append(AgendaItem(title: ""))
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Add a new agenda item")
                }
                .padding(.horizontal)
                List($document.model.agendas, selection: $selection) { $agendaItem in
                    Label(agendaItem.title, systemImage: "note.text")
                        .contextMenu {
                            Button {
                                document.model.agendas.removeAll {
                                    $0.id == agendaItem.id
                                }
                                updateDoc()
                            } label: {
                                Label("Delete", systemImage: "delete.left.fill")
                            }
                        }
                }
                PeerSyncView(syncController: document.syncController)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 250)
            .toolbar {
                ToolbarItem(id: "merge", placement: .principal) {
                    MergeView(document: document)
                        .help("Merge a document into this one")
                }
                ToolbarItem(id: "sync", placement: .status) {
                    SyncView(document: document)
                        .help("Enable peer to peer syncing")
                }
            }
        } detail: {
            EditableAgendaItemView(document: document, agendaItemId: selection)
                // Using .id here is critical to getting views to update
                // upon choosing a new selection on macOS
                .id(selection)
        }
        .onReceive(document.objectWillChange, perform: { _ in
            if !document.model.agendas.contains(where: { agendaItem in
                agendaItem.id == selection
            }) {
                selection = nil
            }
        })
        #if os(iOS)
        // hides the additional navigation stacks that iOS imposes on a document-based app
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func updateDoc() {
        do {
            try document.storeModelUpdates()
        } catch {
            Logger.document
                .error("Error when storing model updates: \(error, privacy: .public)")
        }
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
