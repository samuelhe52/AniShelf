//
//  LibraryEntryPage.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import DataProvider
import SwiftUI

/// One library layout page: its own identity, the layout animation, and the style transition.
struct LibraryEntryPage<Content: View>: View {
    let id: LibraryViewStyle
    let layoutIDs: [LibraryEntryIdentity]
    @ViewBuilder let content: Content

    var body: some View {
        content
            .id(id)
            .animation(.default, value: layoutIDs)
            .transition(LibraryViewTransitions.libraryViewTransition())
    }
}
