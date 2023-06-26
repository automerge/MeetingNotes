# ``MeetingNotes``

An example iOS and macOS document-based application that uses Automerge as an underlying document store to synchronize and seamlessly merge documents.   

## Overview

<!--@START_MENU_TOKEN@-->Text<!--@END_MENU_TOKEN@-->

## Topics


### Document Model

- ``MeetingNotesModel``
- ``AgendaItem``

### Core Application

- ``MeetingNotesApp``
- ``MeetingNotesDocument``
- ``WrappedAutomergeFile``

### Views

- ``ContentView``

### Previews

- ``ContentView_Previews``

### Shared Peer Networking Components

- ``sharedBrowser``
- ``bonjourListener``
- ``applicationServiceListener``
- ``sharedConnection``

### Peer Networking

- ``PeerBrowser``
- ``PeerListener``
- ``PeerConnection``
- ``PeerBrowserDelegate``
- ``PeerConnectionDelegate``

### Peer to Peer Syncing Protocol

- ``AutomergeSyncProtocol``
- ``SyncMessageType`` 
- ``AutomergeSyncProtocolHeader``
- ``applicationServiceParameters()``

### Application Resources

- ``ColorResource``
- ``ImageResource``
