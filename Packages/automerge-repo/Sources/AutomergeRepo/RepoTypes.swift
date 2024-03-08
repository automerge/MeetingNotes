import struct Foundation.Data
import struct Foundation.UUID

/// A type that represents a peer
///
/// Typically a UUID4 in string form.
public typealias PEER_ID = String

/// A type that represents an identity for the storage of a peer.
///
/// Typically a UUID4 in string form. Receiving peers may tie cached sync state for documents to this identifier.
public typealias STORAGE_ID = String

/// The external representation of a document Id.
///
/// Typically a string that is 16 bytes of data encoded in bs58 format.
public typealias MSG_DOCUMENT_ID = String
// internally, DOCUMENT_ID is represented by the internal type DocumentId

/// A type that represents the raw bytes of an Automerge sync message.
public typealias SYNC_MESSAGE = Data

/// A type that represents the raw bytes of a set of encoded changes to an Automerge document.
public typealias CHUNK = Data
