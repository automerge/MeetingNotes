# Meeting Notes, a Document-based SwiftUI app using Automerge

A guided tour of MeetingNotes, a sample iOS and macOS SwiftUI app that uses Automerge for data storage and collaboration.

## Overview

The source for the MeetingNotes app is [available on Github](https://github.com/automerge/MeetingNotes).
The Document-based SwiftUI app illustrates storing and loading a `Codable` model and integrating that Automerge-backed model with SwiftUI controls.
The example supports merging files with offline updates and interactive peer-to-peer syncing in near real time.

### Using Automerge in a Document-based app

MeetingNotes is a document-based SwiftUI app, meaning that it defines a file type, reads and edits files stored on device, focusing on a document to store relevant information.
 [MeetingNotesDocument.swift](https://github.com/automerge/MeetingNotes/blob/main/MeetingNotes/MeetingNotesDocument.swift) contains the core code to support a Document-based SwiftUI app.

The file type that the MeetingNotes defines in the `Info.plist` file is matched in code as an extension on Universal Type Identifier, `com.github.automerge.meetingnotes`:

```swift
extension UTType {
    /// An Automerge document that is CBOR encoded with 
    /// a document identifier.
    static var meetingnote: UTType {
        UTType(exportedAs: "com.github.automerge.meetingnotes")
    }
}
```

The `Info.plist` file defines the type that the app exports with a file extension `.meetingnotes`.
The app's type conforms to the more general Uniform Type Identifiers of [`public.content`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/3551481-content) and [`public.data`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/3551482-data).

MeetingNotes doesn't use the raw bytes that an Automerge document provides for the file format. 
Instead it wraps those bytes to track a unique document identifier created with any new document.
Tracking a unique document identifier provides MeetingNotes with a convenient way to determine if two documents are copies of the same document, or if they were generated independently.
While Automerge supports consistently merging any two document structures, the seamless updates of changes between copies relies on the documents having a shared based history.
Merging two documents that don't share a common history can result in unexpected, although consistent, merge results.

MeetingNotes uses the document identifier to constrain the documents it merges or synchronizes with.
MeetingNotes uses the Codable struct `WrappedAutomergeDocument` to attach the document identifier and encodes it with [CBOR encoding](https://cbor.io).
The CBOR encoding and decoding is provided by the dependency [PotentCodables](https://swiftpackageindex.com/outfoxx/PotentCodables).

```swift
struct WrappedAutomergeDocument: Codable {
    let id: UUID
    let data: Data
    static let fileEncoder = CBOREncoder()
    static let fileDecoder = CBORDecoder()
}
```
Document-based SwiftUI apps expect you to use either a subclass of  [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument) or [ReferenceFileDocument](https://developer.apple.com/documentation/swiftui/referencefiledocument).
MeetingNotes defines `MeetingNotesDocument`, a subclass of `ReferenceFileDocument`.

In the create-a-new-document initializer (`init()`), MeetingNotes creates a new Automerge document along with a new document identifier.
The initializer continues and creates a new, empty model instance and seeds the schema of the model into the Automerge document using `AutomergeEncoder`.

```swift
init() {
    id = UUID()
    doc = Document()
    let newModel = MeetingNotesModel(title: "Untitled")
    model = newModel
    modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
    modelDecoder = AutomergeDecoder(doc: doc)

    do {
        // Establish the schema in the new Automerge document by 
        // encoding the model.
        try modelEncoder.encode(newModel)
    } catch {
        fatalError(error.localizedDescription)
    }
}
```

In the read-a-document-from-data initializer (`init(configuration: ReadConfiguration)`), MeetingNotes attempts to decode the wrapper from the bytes provided by the system, followed by initializing an Automerge document with the bytes embedded within the wrapped document.
If this process succeeds, the initializer uses `AutomergeDecoder` to decode an instance of the model from the Automerge document. 

```swift
required init(configuration: ReadConfiguration) throws {
    guard let filedata = configuration.file.regularFileContents
    else {
        Logger.document.error(
            "Opened file \(String(describing: configuration.file.filename), privacy: .public) has no associated data."
        )
        throw CocoaError(.fileReadCorruptFile)
    }

    // The binary format of the document is a CBOR encoded file. The goal 
    // being to wrap the raw automerge document serialization with an 
    // 'envelope' that includes an origin ID, so that an application can 
    // know if the document stemmed from the same original source or if 
    // they're entirely independent.
    let wrappedDocument = try fileDecoder.decode(
        WrappedAutomergeDocument.self, 
        from: filedata)

    // Set the identifier of this document.
    id = wrappedDocument.id

    // Deserialize the Automerge document from the wrappers data.
    doc = try Document(wrappedDocument.data)

    modelEncoder = AutomergeEncoder(doc: doc, strategy: .createWhenNeeded)
    modelDecoder = AutomergeDecoder(doc: doc)
    do {
        model = try modelDecoder.decode(MeetingNotesModel.self)
    } catch {
        Logger.document.error("error: \(error, privacy: .public)")
        fatalError()
    }
}
```

The required save-the-document method (`snapshot(contentType _: UTType)`) encodes any updates from the model back into the Automerge document.
SwiftUI calls this method at different times, depending on the app platform.
On macOS, it is invoked when the person using MeetingNotes uses "save" through the menu or keyboard shortcut.
However, on iOS, the method is invoked automatically, driven by notifying the UndoManager to let the system know the Document is dirty and an update can be saved.

```swift
func snapshot(contentType _: UTType) throws -> Document {
    try modelEncoder.encode(model)
    return doc
}
```

The snapshot, in turn, is used by `fileWrapper(snapshot: Document, configuration _: WriteConfiguration)` to create a new wrapped document with the updated bytes, and serializes the wrapped document to provide the final bytes to store on device.

```swift
func fileWrapper(
    snapshot: Document, 
    configuration _: WriteConfiguration) throws -> FileWrapper {
    // Using the updated Automerge document returned from snapshot, create
    // a wrapper with the origin ID from the serialized automerge file.
    let wrappedDocument = WrappedAutomergeDocument(
        id: id, 
        data: snapshot.save())

    // Encode that wrapper using CBOR encoding
    let filedata = try fileEncoder.encode(wrappedDocument)

    // And hand that file to the FileWrapper for the operating system 
    // to save, transfer, etc.
    let fileWrapper = FileWrapper(regularFileWithContents: filedata)
    return fileWrapper
}
```

The Document subclass defines two additional helper methods: `storeModelUpdates()` and `getModelUpdates()` to provide a convenient interface point for changes to the Automerge document from synchronization, merging files, or updates to from SwiftUI views.

```swift
/// Updates the Automerge document with the current value from the model.
func storeModelUpdates() throws {
    try modelEncoder.encode(model)
    self.objectWillChange.send()
}

/// Updates the model document with any changed values in the 
/// Automerge document.
func getModelUpdates() throws {
    // Logger.document.debug("Updating model from Automerge document.")
    model = try modelDecoder.decode(MeetingNotesModel.self)
}
```

For more information on building document-based app with SwiftUI, see [Building a Document-Based App with SwiftUI](https://developer.apple.com/documentation/swiftui/building_a_document-based_app_with_swiftui).

### Encoding and Decoding the model

The model used in the app is defined in [MeetingNotesModel.swift](https://github.com/automerge/MeetingNotes/blob/main/MeetingNotes/MeetingNotesModel.swift).
The top level of the model exposes a `Codable` struct that includes `title` and a list of `AgendaItem`.
`AgendaItem` is another `Codable` struct that includes a `title` and an instance of `AutomergeText`.

This model illustrates the Codable encoding of both structs and arrays, as well as the special Automerge type `AutomergeText`, which dynamically reads and updates values from text objects within an Automerge document.
For any updates to the model _other_ than the text updates, the app calls `storeModelUpdates()` on the instance of `ModelNotesDocument` to use an `AutomergeEncoder` to write the updates back into the Automerge `Document` instance.    

### Integrating with SwiftUI Controls and Views

The primary content view for the app is provided by [MeetingNotesDocumentView](https://github.com/automerge/MeetingNotes/blob/main/MeetingNotes/Views/MeetingNotesDocumentView.swift).
This view defines a two-column (list and detail) split view using [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview).

The view contains a property `document`, that references the `MeetingNotesDocument`.
The `document` property is used in the view to display the overall document title as an editable field: 

```swift
TextField("Meeting Title", text: $document.model.title)
    .onSubmit {
        undoManager?.registerUndo(withTarget: document) { _ in }
        updateDoc()
    }
```

On any updates to that field, the view notifies the Undo manager that a change has happened and calls `storeModelUpdates()` on the document.
The Undo manager isn't used to build up a queue of changes to be reversed. 
Instead it is a means to notify the document-based app framework that a change occurred, so that it can mark the document as dirty.
In the macOS app, this provides a visual affordance to let the person using the app know that the document has been updated and can be saved. 
In the iOS app, the framework automatically saves the document.

This main document view also provides a list of the `AgendaItem` instances, includes a button to add new one, and each has a contextual menu option to delete it.

The detail view is provided by [EditableAgendaItemView](https://github.com/automerge/MeetingNotes/blob/main/MeetingNotes/Views/EditableAgendaItemView.swift).
Like the main document view, it maintains a reference to `MeetingNotesDocument` as the property `document.
The view maintains its own `@State` value for an agenda item's title.
The view is passed a unique, stable identifier for each agenda item, which it uses to handle selection from the list view, using `id()` to identify the detail view to make sure it updates when a selection changes. 

The view sets its state using `.onAppear()`, and is refreshed when the view sees an update to the Document's `objectWillChange` publisher.

```swift
.onAppear(perform: {
    if let indexPosition = document.model.agendas.firstIndex(
        where: { $0.id == agendaItemId }) {
        agendaTitle = document.model.agendas[indexPosition].title
    }
})
.onReceive(document.objectWillChange, perform: { _ in
    if let indexPosition = document.model.agendas.firstIndex(
        where: { $0.id == agendaItemId }) {
        agendaTitle = document.model.agendas[indexPosition].title
    }
})
.onChange(of: agendaTitle, perform: { _ in
    updateAgendaItemTitle()
})
```

When the @State value of `agendaTitle` changes, the view writes an updated value back to the Automerge document if the values of the state and document differ.


```swift
private func updateAgendaItemTitle() {
    var store = false
    if let indexPosition = document.model.agendas.firstIndex(
        where: { $0.id == agendaItemId }
    ) {
        if document.model.agendas[indexPosition].title != agendaTitle {
            document.model.agendas[indexPosition].title = agendaTitle
            store = true
        }
        // Encode the model back into the Automerge document if the 
        // values changed.
        if store {
            do {
                // Serialize the changes into the internal 
                // Automerge document.
                try document.storeModelUpdates()
            } catch {
                errorMsg = error.localizedDescription
            }
            // Registering an undo with even an empty handler for 
            // re-do marks the associated document as 'dirty' and 
            // causes SwiftUI to invoke a snapshot to save the file
            // - at least on iOS.
            undoManager?.registerUndo(withTarget: document) { _ in }
        }
    } 
}
```

The `discussion` property of an agenda item is linked to a binding provided by `AutomergeText.textBinding()`, the reference to the text instance looked up from the model using the agenda item's identifier.

```swift
TextEditor(text: bindingForAgendaItem())
```

Each keystroke that updates the discussion is immediately written back to the Automerge document.
By using the `Binding<String>` vended from `AutomergeText`, the app directly reads and updates the view from changes to the Automerge document without having to rebuild the entire view.

```swift
func bindingForAgendaItem() -> Binding<String> {
    if let indexPosition = document.model.agendas.firstIndex(
        where: { $0.id == agendaItemId }
    ) {
        return document
            .model
            .agendas[indexPosition]
            .discussion
            .textBinding()
    } else {
        return .constant("")
    }
}
```

### Model Update Patterns

This example app shows two different patterns of working with data stored within Automerge.
The first uses `Codable` value types, which sets an expectation of decoding the model to read from Automerge, and encoding the model to store any updates.
This pattern is reasonably fast, but does update the entire model - and doing so triggers SwiftUI view rebuilds when those value types are updated.
On a broad scale, this may be inconvenient or untenable for app performance.

The second pattern leverages `Codable`, but does so with a special reference type that provides a reference that directly reads from and writes to the Automerge document.
By using a `Codable` reference type, the app can leverage the capability of `AutomergeEncoder` to establish the needed objects within a new Automerge document, effecting "seeding the schema".
Beyond that, it is the reposibility of the `AutomergeText` object to notify of changes to ensure SwiftUI views are refreshed as appropriate.

The `AutomergeText` source provides an example of how you can structure your own reference types to achieve this sort of performance, if that need is critical to you.
In practice, doing this extra work correlates well to wanting to expose live-collaboration capabilities, where one or more people are doing frequent updates and the documents are likewise frequently synchronizing.
In MeetingNotes, by using a `Codable` reference type of `AutomergeText`, the app gets a notable performance increase when collaboratively editing a `discussion` property while live-syncing with another peer.

### Merging documents

The main app view includes a toolbar button displaying [MergeView.swift](https://github.com/automerge/MeetingNotes/blob/main/MeetingNotes/Views/MergeView.swift).
`MergeView` provides a button that uses [`fileImporter`](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)) to attempt to load another instance of the MeetingNotes document type from device storage.
This button illustrates how to seamlessly merge in updates from a copy made of the original document.

Upon loading the document, it calls the helper method `mergeDocument` on `MeetingNotesDocument` to decode the document identifier, and if identical to the current document, merges any updates using `Document.merge(other:)`.

```swift
func mergeFile(_ fileURL: URL) -> Result<Bool, Error> {
    precondition(fileURL.isFileURL)
    do {
        let fileData = try Data(contentsOf: fileURL)
        let newWrappedDocument = try fileDecoder.decode(
            WrappedAutomergeDocument.self, 
            from: fileData)
        if newWrappedDocument.id != self.id {
            throw MergeError.NoSharedHistory
        }
        let newAutomergeDoc = try Document(newWrappedDocument.data)
        try doc.merge(other: newAutomergeDoc)
        model = try modelDecoder.decode(MeetingNotesModel.self)
        return .success(true)
    } catch {
        return .failure(error)
    }
}
```

### Syncing Documents

With a document-based SwiftUI app, the SwiftUI app framework owns the lifetime of a `ReferenceFileDocument` subclass.
If the file saved from the document-based app is stored in iCloud, the operating system may destroy an existing instance and re-create it from the contents on device - most notably after having replicated the file with iCloud.
There may be other instances of where the document can be rebuilt, but the important aspect to note is that SwiftUI is in control of that instance's lifecycle.

To provide peer to peer syncing, MeetingNotes uses the [automerge-repo-swift package](https://github.com/automerge/automerge-repo-swift).
It creates a single globally available instance of a repository to track documents that are loaded by the SwiftUI document-based app.
To provide the network connections, it also creates an instance of a `WebSocketprovider` and `PeerToPeerProvider`, and adds those to the repository at the end of app initialization:

```swift
public let repo = Repo(sharePolicy: SharePolicy.agreeable)
public let websocket = WebSocketProvider(.init(reconnectOnError: true))
public let peerToPeer = PeerToPeerProvider(
    PeerToPeerProviderConfiguration(
        passcode: "AutomergeMeetingNotes",
        reconnectOnError: true,
        autoconnect: false
    )
)

/// The document-based Meeting Notes application.
@main
struct MeetingNotesApp: App {
    ...
    init() {
        Task {
            // Enable network adapters
            await repo.addNetworkAdapter(adapter: websocket)
            await repo.addNetworkAdapter(adapter: peerToPeer)
        }
    }
}

```

The SwiftUI document-based API is all synchronous, so loading an Automerge document it provides is down within the view when it first appears.

```
.task {
    // SwiftUI controls the lifecycle of MeetingNoteDocument instances,
    // including sometimes regenerating them when disk contents are updated
    // in the background, so register the current instance with the
    // sync coordinator as they become visible.
    do {
        _ = try await repo.create(doc: document.doc, id: document.id)
    } catch {
        fatalError("Crashed loading the document: \(error.localizedDescription)")
    }
}
```

Once added to the repository, toolbar buttons on the `MeetingNotesDocumentView` toggle a WebSocket connection or activate the peer to peer networking.
`PeerSyncView` provides information about available peers on your local network, and allows you to explicitly connect to those peers.
The repository handles syncing automatically as the Automerge document is updated.
Both the WebSocket and peer-to-peer networking implement the Automerge sync protocol over their respective transports.
