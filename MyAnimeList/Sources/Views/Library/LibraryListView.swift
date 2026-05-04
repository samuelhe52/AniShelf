//
//  LibraryListView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/29.
//

import DataProvider
import SwiftUI

struct LibraryListView: View {
    let store: LibraryStore
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Environment(\.toggleFavorite) var toggleFavorite

    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?

    var body: some View {
        ScrollViewReader { proxy in
            List(store.libraryOnDisplay, id: \.tmdbID) { entry in
                AnimeEntryListRow(
                    entry: entry,
                    onSelect: { scrolledID = entry.tmdbID },
                    onOpenDetails: { interaction.detailingEntry = entry }
                )
                .highlightEffect(
                    showHighlight: interaction.highlightBinding(
                        for: entry,
                        highlightedEntryID: $highlightedEntryID
                    ),
                    delay: 0.2
                )
                .contextMenu {
                    interaction.contextMenu(
                        for: entry,
                        store: store,
                        toggleFavorite: toggleFavorite
                    )
                } preview: {
                    EntryContextMenuPreview(entry: entry)
                        .onAppear { scrolledID = entry.tmdbID }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash") {
                        interaction.prepareDeletion(for: entry)
                    }
                    .tint(.red)
                }
                .swipeActions(edge: .leading) {
                    Button("Edit", systemImage: "pencil") {
                        interaction.setEditingEntry(entry)
                    }
                    .tint(.blue)
                }
                .listRowInsets(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
                .listRowSeparator(.visible)
                .listRowSeparatorTint(.white.opacity(0.06))
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .animation(.default, value: store.sortReversed)
            .animation(.default, value: store.sortStrategy)
            .animation(.default, value: store.filters)
            .onChange(of: scrolledID, initial: true) {
                if let scrolledID {
                    proxy.scrollTo(scrolledID)
                }
            }
        }
        .libraryEntryInteractionOverlays(
            state: interaction,
            store: store,
            scrolledID: $scrolledID
        )
    }
}
