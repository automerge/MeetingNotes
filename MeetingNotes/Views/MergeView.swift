import SwiftUI

struct MergeView: View {
    @ObservedObject var document: MeetingNotesDocument
    
    var body: some View {
        Text("Merging View...")
    }
}

struct MergeView_Previews: PreviewProvider {
    static var previews: some View {
        MergeView(document: MeetingNotesDocument.sample())
    }
}
