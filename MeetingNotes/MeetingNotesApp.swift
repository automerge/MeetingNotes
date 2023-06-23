//
//  MeetingNotesApp.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 6/23/23.
//

import SwiftUI

@main
struct MeetingNotesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MeetingNotesDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
