import Automerge
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// What I'd like to have as my "meeting notes" schema:
//
// - ROOT {
//     "id" - UUID (Scalar) // for comparing origins for sync
//     "title" - String (scalar)
//     "attendees" - [ String (scalar) ]
//     "agenda" - [
//        AgendaItem {
//           "title": String (scalar)
//           "discussion": Text
//        }
//     ]
//   }

struct AgendaItem: Codable {
    var title: String
    var discussion: Text
}

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
