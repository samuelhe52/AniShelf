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

    @Environment(\.editMode) private var editMode

    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?

    var body: some View {
        ScrollViewReader { proxy in
            List(store.libraryDisplayItems, selection: selectionBinding) { item in
                rowContent(for: item)
            }
            .listStyle(.plain)
            .environment(\.editMode, editMode)
            .animation(.default, value: store.groupStrategy)
            .animation(.default, value: store.sortReversed)
            .animation(.default, value: store.sortStrategy)
            .animation(.default, value: store.filters)
            .onAppear {
                if let scrolledID { proxy.scrollTo(scrolledID) }
            }
            .onChange(of: interaction.isMultiSelecting, initial: true) { _, isMultiSelecting in
                withAnimation {
                    editMode?.wrappedValue = isMultiSelecting ? .active : .inactive
                }
            }
            .onChange(of: scrolledID) {
                if let scrolledID {
                    withAnimation(.bouncy) {
                        proxy.scrollTo(scrolledID)
                    }
                }
            }
        }
        .libraryEntryInteractionOverlays(
            state: interaction,
            deleteEntry: { entry in
                store.deleteEntry(entry) { scrolledID = $0 }
            },
            detailRepository: store.repository
        )
    }

    @ViewBuilder
    private func rowContent(for item: LibraryEntryDisplayItem) -> some View {
        AnimeEntryListRow(
            entry: item.entry,
            snapshot: item.snapshot,
            onTap: { scrolledID = item.id },
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
        .tag(item.id)
        .listRowInsets(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
        .listRowSeparator(.visible)
        .listRowSeparatorTint(.white.opacity(0.06))
        .listRowBackground(Color.clear)
        .contextMenu {
            interaction.contextMenu(
                for: item.entry,
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
    }

    private var selectionBinding: Binding<Set<Int>> {
        Binding(
            get: { interaction.selectedEntryIDs },
            set: { interaction.selectedEntryIDs = $0 }
        )
    }
}
