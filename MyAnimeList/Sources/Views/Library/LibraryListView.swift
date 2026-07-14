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

    @State private var listEditMode: EditMode = .inactive

    let displayItems: [LibraryEntryDisplayItem]
    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?

    var body: some View {
        ScrollViewReader { proxy in
            List(displayItems, selection: listSelection) { item in
                rowContent(for: item)
            }
            .listStyle(.plain)
            .environment(\.editMode, $listEditMode)
            .animation(.default, value: store.groupStrategy)
            .animation(.default, value: store.sortReversed)
            .animation(.default, value: store.sortStrategy)
            .animation(.default, value: store.filters)
            .onAppear {
                if let scrolledID { proxy.scrollTo(scrolledID) }
            }
            .onChange(of: interaction.isMultiSelecting, initial: true) { _, isMultiSelecting in
                withAnimation {
                    listEditMode = isMultiSelecting ? .active : .inactive
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
    }

    @ViewBuilder
    private func rowContent(for item: LibraryEntryDisplayItem) -> some View {
        AnimeEntryListRow(
            entry: item.entry,
            snapshot: item.snapshot,
            onTap: {
                scrolledID = item.id
                interaction.focus(item.entry)
            },
            onOpenDetails: {
                guard !interaction.isMultiSelecting else { return }
                scrolledID = item.id
                interaction.openDetails(for: item.entry)
            }
        )
        .opacity(
            !interaction.isMultiSelecting || interaction.isSelected(item.id) ? 1 : 0.48
        )
        .scaleEffect(
            !interaction.isMultiSelecting || interaction.isSelected(item.id) ? 1 : 0.985
        )
        .animation(
            .smooth(duration: 0.18),
            value: interaction.isSelected(item.id)
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
            if !interaction.isMultiSelecting {
                Button("Delete", systemImage: "trash") {
                    interaction.prepareDeletion(for: item.entry)
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .leading) {
            if !interaction.isMultiSelecting {
                Button("Edit", systemImage: "pencil") {
                    interaction.setEditingEntry(item.entry)
                }
                .tint(.blue)
            }
        }
    }

    private var listSelection: Binding<Set<Int>>? {
        guard interaction.isMultiSelecting else { return nil }

        return Binding(
            get: { interaction.selectedEntryIDs },
            set: { interaction.selectedEntryIDs = $0 }
        )
    }

}
