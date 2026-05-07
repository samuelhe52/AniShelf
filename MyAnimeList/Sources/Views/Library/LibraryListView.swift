//
//  LibraryListView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/29.
//

import DataProvider
import SwiftUI

struct LibraryListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Environment(\.toggleFavorite) var toggleFavorite

    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?

    var body: some View {
        ScrollViewReader { proxy in
            List(store.libraryDisplayItems) { item in
                AnimeEntryListRow(
                    entry: item.entry,
                    snapshot: item.snapshot,
                    onSelect: { scrolledID = item.id },
                    onOpenDetails: {
                        scrolledID = item.id
                        interaction.detailingEntry = item.entry
                    }
                )
                .highlightEffect(
                    showHighlight: interaction.highlightBinding(
                        for: item.id,
                        highlightedEntryID: $highlightedEntryID
                    ),
                    delay: 0.2
                )
                .contextMenu {
                    interaction.contextMenu(
                        for: item.entry,
                        store: store,
                        toggleFavorite: toggleFavorite
                    )
                } preview: {
                    EntryContextMenuPreview(snapshot: item.snapshot)
                        .onAppear { scrolledID = item.id }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash") {
                        interaction.prepareDeletion(for: item.entry)
                    }
                    .tint(.red)
                }
                .swipeActions(edge: .leading) {
                    Button("Edit", systemImage: "pencil") {
                        interaction.setEditingEntry(item.entry)
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
