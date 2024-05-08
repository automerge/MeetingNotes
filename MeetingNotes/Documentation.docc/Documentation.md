# ``MeetingNotes``

An example iOS and macOS document-based application that uses Automerge as an underlying document store to synchronize and seamlessly merge documents.   

## Overview

The Document-based SwiftUI app illustrates storing and loading a [Codable](https://developer.apple.com/documentation/swift/codable) model and integrating [Automerge](https://automerge.org/) backed models with the SwiftUI controls.
The app illustrates the file merging capabilities with an Automerge-backed document and interactive peer-to-peer syncing of documents in near real time.

For a walk-through of the highlights of how the application functions, and how it uses the [automerge-swift library](https://automerge.org/automerge-swift/documentation/automerge/) in coordination with Bonjour networking and SwiftUI, read <doc:AppWalkthrough>.
The source for the MeetingNotes app is [available on Github](https://github.com/automerge/MeetingNotes).

## Topics

### Document Model

- <doc:AppWalkthrough>
- ``MeetingNotesModel``
- ``AgendaItem``

- ``MeetingNotes/MeetingNotesDocument``
- ``MeetingNotes/WrappedAutomergeDocument``
- ``MeetingNotes/UniformTypeIdentifiers/UTType/meetingnote``

### Core Application

- ``MeetingNotesApp``
- ``MergeError``
- ``UserDefaultKeys``

### Global Variables

- ``repo``
- ``websocket``
- ``peerToPeer``

### Logger extensions

- ``MeetingNotes/os/Logger/document``
- ``MeetingNotes/os/Logger/syncflow``

### Views

- ``MeetingNotesDocumentView``
- ``EditableAgendaItemView``
- ``AvailablePeerView``
- ``PeerConnectionView``
- ``PeerSyncView``
- ``SyncStatusView``
- ``MergeView``
- ``ExportView``
- ``WebSocketStatusView``

### Previews

- ``MeetingNotesDocumentView_Previews``
- ``EditableAgendaItemListView_Previews``
- ``PeerBrowserView_Previews``
- ``MergeView_Previews``
- ``SyncView_Previews``
- ``ExportView_Previews``
- ``WebSocketView_Previews``

### Application Resources

- ``ColorResource``
- ``ImageResource``
