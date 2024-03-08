import class Automerge.Document

/// A weak reference to an Automerge document
///
/// Allow a global singleton keep references to documents without incurring memory leaks as Documents are opened and
/// closed.
final class WeakDocumentRef {
    weak var value: Automerge.Document?

    init(_ value: Automerge.Document? = nil) {
        self.value = value
    }
}
