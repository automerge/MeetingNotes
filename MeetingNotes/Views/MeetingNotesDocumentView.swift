import AutomergeRepo
import OSLog
import SwiftUI

/// The primary document view for a MeetingNotes document.
@MainActor
struct MeetingNotesDocumentView: View {
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
                    .onSubmit {
                        undoManager?.registerUndo(withTarget: document) { _ in }
                        updateDoc()
                    }
                    .autocorrectionDisabled()
                    .padding(.horizontal)
                HStack {
                    Spacer()
                    Button {
                        document.model.agendas.append(AgendaItem(title: ""))
                        updateDoc()
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
                HStack(alignment: .firstTextBaseline) {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        ExportView(document: document)
                            .help("Exports the underlying Automerge document")
                            .padding(.leading)
                    }
                    PeerSyncView(documentId: document.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 250)
            .toolbar {
                ToolbarItem(id: "merge", placement: .principal) {
                    MergeView(document: document)
                        .help("Merge a document into this one")
                }
                ToolbarItem(id: "sync", placement: .status) {
                    SyncStatusView()
                        .help("Enable peer to peer syncing")
                }
                ToolbarItem(id: "websocket", placement: .status) {
                    WebSocketStatusView(document: document)
                        .help("Enable websocket syncing")
                }
            }
        } detail: {
            EditableAgendaItemView(document: document, agendaItemId: selection)
                // Using .id here is critical to getting views to update
                // upon choosing a new selection on macOS
                .id(selection)
        }
        .task {
            // SwiftUI controls the lifecycle of MeetingNoteDocument instances,
            // including sometimes regenerating them when disk contents are updated
            // in the background, so register the current instance with the
            // sync coordinator as they become visible.
            do {
                _ = try await repo.import(handle: DocHandle(id: document.id, doc: document.doc))
            } catch {
                fatalError("Crashed loading the document: \(error.localizedDescription)")
            }
        }
        .onReceive(document.objectWillChange, perform: { _ in
            // When we see the document itself has been updated, send a little "note" to the undoManager
            // to let it know that something has changed, so that it can "serialize and save" the updates
            // when the Document-based system is ready to do so automagically.
            // Without this in place, a document that was updated over the network by a repository would
            // never provide any detail to the SwiftUI Document-based control mechanisms that it needs to
            // wrangle a local copy into safety (at least automatically). This was quite the tricky little
            // bug to resolve on iOS where that automagic stuff rules, and there's not an explicit "save"
            // menu/keyboard shortcut to invoke.
            undoManager?.registerUndo(withTarget: document) { _ in }
            // And just to be safe, verify that now that stuff has changed, the agendaItem we have stored
            // as the current view selection does, in fact, still exist - if not, set the selection to nil.
            if !document.model.agendas.contains(where: { agendaItem in
                agendaItem.id == selection
            }) {
                selection = nil
            }
        })
        #if os(iOS)
        // Hides the additional navigation stacks that iOS imposes on a document-based app
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

/// Preview of the MeetingNotes document view.
struct MeetingNotesDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(iOS)
        NavigationView {
            MeetingNotesDocumentView(document: MeetingNotesDocument.sample())
        }
        #else
        if #available(macOS 14.0, iOS 17.0, *) {
            MeetingNotesDocumentView(document: MeetingNotesDocument.sample())
        } else {}
        #endif
    }
}
