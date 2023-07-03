//
//  AgendaItemListView.swift
//  MeetingNotes
//
//  Created by Joseph Heck on 7/1/23.
//

import SwiftUI
import Automerge

struct AgendaItemListView: View {
    let agendaItemBinding: Binding<AgendaItem>
    var body: some View {
        VStack {
            Text("Hello, World!")
            TextField(text: agendaItemBinding.title) {
                Text(";-)")
            }
        }
    }
}

struct AgendaItemListView_Previews: PreviewProvider {
    static var previews: some View {
        AgendaItemListView(agendaItemBinding: .constant(AgendaItem(title: "", discussion: Automerge.Text(""))))
    }
}
