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

    let detailActions: LibraryEntryDetailActions
    let displayItems: [LibraryEntryDisplayItem]
    @Binding var scrolledID: LibraryEntryIdentity?
    let scrollRequest: LibraryScrollRequest?
    let highlightRequest: LibraryHighlightRequest?
    #if os(macOS)
        @Environment(MacLibrarySelection.self) private var selection
        @FocusState private var isListFocused: Bool
    #endif

    var body: some View {
        ScrollViewReader { proxy in
            List(
                displayItems,
                selection: listSelection
            ) { item in
                rowContent(for: item)
            }
            #if os(macOS)
                // The inset style draws a rounded, inset selection like Mail's instead of an
                // edge-to-edge bar.
                .listStyle(.inset)
                .focused($isListFocused)
                // The native List menu and open action act on the clicked row or the
                // selection; double-click and Return show the entry in the inspector.
                .contextMenu(forSelectionType: LibraryEntryIdentity.self) { ids in
                    if ids.count == 1, let entry = entry(for: ids.first) {
                        interaction.contextMenu(for: entry, toggleFavorite: toggleFavorite, editEntry: editEntry)
                    }
                } primaryAction: { ids in
                    if ids.count == 1, let entry = entry(for: ids.first) { openDetails(for: entry) }
                }
            #else
                .listStyle(.plain)
            #endif
            .preferredNavigationBarScrollEdgeEffect()
            .selectionEditMode(interaction.isMultiSelecting)
            .animation(LibraryViewTransitions.selectionModeAnimation(), value: interaction.isMultiSelecting)
            .animation(.default, value: store.groupStrategy)
            .animation(.default, value: store.sortReversed)
            .animation(.default, value: store.sortStrategy)
            .animation(.default, value: store.filters)
            .onAppear {
                if let scrolledID { proxy.scrollTo(scrolledID) }
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

    #if os(macOS)
        /// Desktop lists select natively into the window's selection.
        private var listSelection: Binding<Set<LibraryEntryIdentity>> {
            Binding(
                get: { selection.ids },
                set: { ids in
                    // Keep arrow keys in the list after a click instead of the sidebar.
                    isListFocused = true
                    selection.select(ids)
                }
            )
        }

        private func entry(for id: LibraryEntryIdentity?) -> AnimeEntry? {
            displayItems.first { $0.id == id }?.entry
        }
    #else
        private var listSelection: Binding<Set<LibraryEntryIdentity>> {
            // Keep native selection configured while edit mode animates out.
            // Browsing taps must not add items to the batch selection.
            Binding(
                get: { interaction.selectedEntryIDs },
                set: { selectedEntryIDs in
                    guard interaction.isMultiSelecting else { return }
                    interaction.selectedEntryIDs = selectedEntryIDs
                }
            )
        }
    #endif

    @ViewBuilder
    private func rowContent(for item: LibraryEntryDisplayItem) -> some View {
        AnimeEntryListRow(
            entry: item.entry,
            snapshot: item.snapshot,
            tapGesturesEnabled: rowTapGesturesEnabled,
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
        #if !os(macOS)
            .opacity(
                !interaction.isMultiSelecting || interaction.isSelected(item.id) ? 1 : 0.48
            )
            .scaleEffect(
                !interaction.isMultiSelecting || interaction.isSelected(item.id) ? 1 : 0.985
            )
            .animation(
                .smooth(duration: 0.18),
                value: !interaction.isMultiSelecting || interaction.isSelected(item.id)
            )
        #endif
        .highlightEffect(trigger: highlightRequest?.trigger(for: item.id))
        .tag(item.id)
        .listRowInsets(rowInsets)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(.white.opacity(0.06))
        #if !os(macOS)
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
        #endif

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

    private var rowInsets: EdgeInsets {
        #if os(macOS)
            .init(top: 4, leading: 8, bottom: 4, trailing: 8)
        #else
            .init(top: 8, leading: 10, bottom: 8, trailing: 10)
        #endif
    }

    /// Desktop rows leave clicks to the list's native selection.
    private var rowTapGesturesEnabled: Bool {
        #if os(macOS)
            false
        #else
            !interaction.isMultiSelecting
        #endif
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
