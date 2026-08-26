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

    @State private var listEditMode: EditMode = .inactive

    let detailActions: LibraryEntryDetailActions
    let displayItems: [LibraryEntryDisplayItem]
    @Binding var scrolledID: LibraryEntryIdentity?
    let scrollRequest: LibraryScrollRequest?
    @Binding var highlightedEntryID: LibraryEntryIdentity?

    var body: some View {
        @Bindable var interaction = interaction

        ScrollViewReader { proxy in
            List(
                displayItems,
                selection: interaction.isMultiSelecting
                    ? $interaction.selectedEntryIDs
                    : nil
            ) { item in
                rowContent(for: item)
            }
            .listStyle(.plain)
            .preferredNavigationBarScrollEdgeEffect()
            .environment(\.editMode, $listEditMode)
            .animation(.default, value: store.groupStrategy)
            .animation(.default, value: store.sortReversed)
            .animation(.default, value: store.sortStrategy)
            .animation(.default, value: store.filters)
            .onAppear {
                if let scrolledID { proxy.scrollTo(scrolledID) }
            }
            .onChange(of: interaction.isMultiSelecting, initial: true) { _, isMultiSelecting in
                // Match the selection-mode curve so the edit-mode transition
                // doesn't race the row and toolbar animations on dismiss.
                withAnimation(LibraryViewTransitions.selectionModeAnimation()) {
                    listEditMode = isMultiSelecting ? .active : .inactive
                }
            }
            .onChange(of: scrollRequest) {
                if let entryID = scrollRequest?.entryID {
                    withAnimation(.bouncy) {
                        proxy.scrollTo(entryID)
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
            tapGesturesEnabled: !interaction.isMultiSelecting,
            onTap: {
                scrolledID = item.id
                interaction.focus(item.entry)
            },
            onOpenDetails: {
                guard !interaction.isMultiSelecting else { return }
                scrolledID = item.id
                openDetails(for: item.entry)
            },
            onToggleFavorite: toggleFavorite
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
                toggleFavorite: toggleFavorite,
                editEntry: editEntry
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
                    editEntry(item.entry)
                }
                .tint(.blue)

                interaction.shareButton(for: item.entry)
                    .tint(.indigo)
            }
        }
    }

    private func openDetails(for entry: AnimeEntry) {
        detailActions.open(entry)
    }

    private func editEntry(_ entry: AnimeEntry) {
        detailActions.edit(entry)
    }

    private func toggleFavorite(_ entry: AnimeEntry) {
        store.repository.toggleFavorite(entry)
    }

}
