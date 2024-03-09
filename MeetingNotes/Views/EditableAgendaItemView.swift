import Automerge
import OSLog
import SwiftUI

/// A view that provides an editable view of an agenda item.
@MainActor
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
    private var errorMsg: String = ""

    @FocusState
    private var titleIsFocused: Bool

    init(document: MeetingNotesDocument, agendaItemId: UUID?) {
        self.document = document
        self.agendaItemId = agendaItemId
    }

    func bindingForAgendaItem() -> Binding<String> {
        if let indexPosition = document.model.agendas.firstIndex(where: { $0.id == agendaItemId }) {
            return document.model.agendas[indexPosition].discussion.textBinding()
        } else {
            return .constant("")
        }
    }

    var body: some View {
        if agendaItemId != nil {
            VStack {
                HStack {
                    Image(systemName: "note.text")
                    TextField(text: $agendaTitle) {
                        Text("Enter a title for the agenda item.")
                    }
                    .padding(2)
                    .border(.gray)
                }.padding(.horizontal)

                TextEditor(text: bindingForAgendaItem())
                    .padding(2)
                    .border(Color.black)
                    .padding()

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.callout)
                        .foregroundStyle(Color.red)
                }
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        document.model.agendas.removeAll {
                            $0.id == agendaItemId
                        }
                        do {
                            try document.storeModelUpdates()
                        } catch {
                            Logger.document.error("Error when storing model updates: \(error, privacy: .public)")
                        }
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.borderedProminent)
                }.padding([.horizontal, .bottom])
            }
            .focused($titleIsFocused)
            .onAppear(perform: {
                if let indexPosition = document.model.agendas.firstIndex(where: { $0.id == agendaItemId }) {
                    agendaTitle = document.model.agendas[indexPosition].title
                }
            })
            .onReceive(document.objectWillChange, perform: { _ in
                if let indexPosition = document.model.agendas.firstIndex(where: { $0.id == agendaItemId }) {
                    agendaTitle = document.model.agendas[indexPosition].title
                }
            })
            .onChange(of: agendaTitle, perform: { _ in
                updateAgendaItemTitle()
            })
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                // hides the extra space at the top of the view that comes
                // from the default navigation title.
                .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            Text("Select an agenda item")
        }
    }

    private func updateAgendaItemTitle() {
        var store = false
        if let indexPosition = document.model.agendas.firstIndex(where: { $0.id == agendaItemId }) {
            if document.model.agendas[indexPosition].title != agendaTitle {
                document.model.agendas[indexPosition].title = agendaTitle
                store = true
            }
            // Encode the model back into the Automerge document if the values changed.
            if store {
                do {
                    // Serialize the changes into the internal Automerge document.
                    try document.storeModelUpdates()
                } catch {
                    errorMsg = error.localizedDescription
                }
                // Registering an undo with even an empty handler for re-do marks
                // the associated document as 'dirty' and causes SwiftUI to invoke
                // a snapshot to save the file - on iOS.
                undoManager?.registerUndo(withTarget: document) { _ in }
            }
        } else {
            if let localId = agendaItemId {
                Logger.document
                    .warning(
                        "Displaying an AgendaItem page with no matching UUID: \(localId.uuidString, privacy: .public)"
                    )
            } else {
                Logger.document.warning("Displaying an AgendaItem page with no matching UUID: nil")
            }
        }
    }
}

/// Preview of an editable agenda item view.
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
