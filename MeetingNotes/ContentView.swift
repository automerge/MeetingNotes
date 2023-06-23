//
//  ContentView.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 6/23/23.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MeetingNotesDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(MeetingNotesDocument()))
    }
}
