import Automerge
import Foundation

/// An individual agenda item tracked by meeting notes.
/// The `discussion` property is the type `Text` is from Automerge, and represents a collaboratively edited string.
struct AgendaItem: Codable, Hashable {
    var title: String
    var discussion: Text
}

/// The top-level application model for Meeting Notes.
///
/// The `id` is meant to provide a root document identifier for use in comparing synced or external documents to
/// determine if they share a common history.
///
/// The overall document schema is laid out to map into Automerge using the following schema:
/// ```
/// ROOT {
///   "id" - UUID (as a scalar value)
///   "title" - String (as a scalar value)
///   "attendees" - [ String (as a scalar value) ]
///   "agenda" - [
///      AgendaItem {
///        "title": String (as a scalar value)
///        "discussion": Text (collaborative sync for edits)
///      }
///   ]
/// }
/// ```
struct MeetingNotesModel: Codable, Identifiable {
    let id: UUID
    var title: String
    var attendees: [String]
    var agenda: [AgendaItem]

    init(title: String) {
        id = UUID()
        self.title = title
        attendees = []
        agenda = []
    }
}
