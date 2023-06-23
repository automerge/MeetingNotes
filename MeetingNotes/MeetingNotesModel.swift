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
//     "summary" - Text (collaborative)
//   }

struct MeetingNotesModel: Codable, Identifiable {
    let id: UUID
    var title: String
    var summary: Text

    init(title: String, summary: Text) {
        id = UUID()
        self.title = title
        self.summary = summary
    }
}
