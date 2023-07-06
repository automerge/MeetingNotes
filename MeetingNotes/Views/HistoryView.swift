import SwiftUI

struct HistoryView: View {
    @ObservedObject var document: MeetingNotesDocument
    
    @State var score: Int = 0
        var intProxy: Binding<Double>{
            Binding<Double>(get: {
                //returns the score as a Double
                return Double(score)
            }, set: {
                //rounds the double to an Int
                score = Int($0)
            })
        }
    
    var body: some View {
        VStack {
            Text("Document has \(document.doc.heads().count) changes")
            if document.doc.heads().count > 1 {
                Slider(value: intProxy,
                       in: 0.0...Double(document.doc.heads().count),
                       step: 1.0,
                       onEditingChanged: { _ in
                    print(score.description)
                })
            }
            Text("History View...")
            Spacer()
        }
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView(document: MeetingNotesDocument.sample())
    }
}
