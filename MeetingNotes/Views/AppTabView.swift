//
//  AppTabView.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 7/6/23.
//

import SwiftUI

struct AppTabView: View {
    @ObservedObject var document: MeetingNotesDocument

    var body: some View {
        TabView {
            MeetingNoteDocumentView(document: document)
                .tabItem {
                    Label("Editor", systemImage: "doc.fill")
                }
            MergeView()
                .tabItem {
                    Label("Merge", systemImage: "doc.badge.gearshape.fill")
                }
        }
    }
}

struct AppTabView_Previews: PreviewProvider {
    static var previews: some View {
        AppTabView(document: MeetingNotesDocument.sample())
    }
}
