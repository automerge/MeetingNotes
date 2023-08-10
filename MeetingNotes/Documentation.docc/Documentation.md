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
- ``sharedSyncCoordinator``
- ``MeetingNotesDefaultKeys``
- ``MergeError``

### Logger extensions

- ``MeetingNotes/os/Logger/document``
- ``MeetingNotes/os/Logger/syncController``
- ``MeetingNotes/os/Logger/syncConnection``

### Views

- ``MeetingNotesDocumentView``
- ``EditableAgendaItemView``
- ``NWBrowserResultItemView``
- ``PeerSyncView``
- ``SyncConnectionView``
- ``MergeView``
- ``SyncView``

### Previews

- ``MeetingNotesDocumentView_Previews``
- ``EditableAgendaItemListView_Previews``
- ``PeerBrowserView_Previews``
- ``MergeView_Previews``
- ``SyncView_Previews``

### Shared Peer Networking Components

- ``DocumentSyncCoordinator``
- ``SyncConnection``
- ``TXTRecordKeys``

### Peer to Peer Syncing Protocol

- ``AutomergeSyncProtocol``
- ``SyncMessageType`` 
- ``AutomergeSyncProtocolHeader``
- ``MeetingNotes/Network/NWParameters/peerSyncParameters(documentId:)``

### Application Resources

- ``ColorResource``
- ``ImageResource``
