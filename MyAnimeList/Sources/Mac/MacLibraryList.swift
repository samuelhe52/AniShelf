//
//  MacLibraryList.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// The Mac library list.
    ///
    /// It selects natively into the window's `MacLibrarySelection`;
    /// double-click and Return show the entry in the inspector. The iOS list is
    /// `LibraryListView`.
    struct MacLibraryList: View {
        @Environment(LibraryStore.self) private var store
        @Environment(LibraryBrowseScope.self) private var scope
        @Environment(LibraryEntryActionState.self) private var actions
        @Environment(MacLibrarySelection.self) private var selection
        @FocusState private var isListFocused: Bool
        @State private var openInRequest: EntryOpenInRequest?
        @State private var visibleEntries = LibraryVisibleEntryTracker()

        let detailActions: LibraryEntryDetailActions
        let displayItems: [LibraryEntryDisplayItem]
        let bookmark: LibraryScrollBookmark
        let scrollInputs: LibraryScrollInputs
        let highlightRequest: LibraryHighlightRequest?

        var body: some View {
            ScrollViewReader { proxy in
                List(
                    displayItems,
                    selection: listSelection
                ) { item in
                    rowContent(for: item)
                }
                // The inset style draws a rounded, inset selection like Mail's instead of an
                // edge-to-edge bar.
                .listStyle(.inset)
                .focused($isListFocused)
                // The native List menu and open action act on the clicked row or the
                // selection; double-click and Return show the entry in the inspector.
                .contextMenu(forSelectionType: LibraryEntryIdentity.self) { ids in
                    if ids.count == 1, let entry = entry(for: ids.first) {
                        actions.contextMenu(for: entry, toggleFavorite: toggleFavorite, editEntry: editEntry)
                    }
                } primaryAction: { ids in
                    if ids.count == 1, let entry = entry(for: ids.first) { detailActions.open(entry) }
                }
                .preferredNavigationBarScrollEdgeEffect()
                .animation(.default, value: scope.groupStrategy)
                .animation(.default, value: scope.sortReversed)
                .animation(.default, value: scope.sortStrategy)
                .animation(.default, value: scope.filters)
                // The table reports what is on screen; SwiftUI's row visibility and scroll
                // phases are unreliable for the Mac List (docs-ai 038).
                .macLibraryListScrollObserver(
                    visibleRowsChanged: { rows in visibleEntries.setVisibleRows(rows, recordingInto: bookmark) },
                    userDidScroll: { bookmark.userDidScroll() }
                )
                .libraryScrollBookmark(
                    bookmark,
                    tracker: visibleEntries,
                    displayIDs: displayItems.map(\.id),
                    inputs: scrollInputs,
                    proxy: proxy
                )
            }
        }

        /// Desktop lists select natively into the window's selection.
        private var listSelection: Binding<Set<LibraryEntryIdentity>> {
            Binding(
                get: { selection.ids },
                set: { ids in
                    // Keep arrow keys in the list after a click instead of the sidebar.
                    isListFocused = true
                    // Arrow keys scroll the list natively without a user scroll phase, so any
                    // selection change counts as the user moving on from a restored position.
                    bookmark.userDidScroll()
                    selection.select(ids)
                }
            )
        }

        private func entry(for id: LibraryEntryIdentity?) -> AnimeEntry? {
            displayItems.first { $0.id == id }?.entry
        }

        private func rowContent(for item: LibraryEntryDisplayItem) -> some View {
            // Rows leave clicks to the list's native selection.
            AnimeEntryListRow(
                entry: item.entry,
                snapshot: item.snapshot,
                tapGesturesEnabled: false,
                onToggleFavorite: toggleFavorite
            )
            .highlightEffect(trigger: highlightRequest?.trigger(for: item.id))
            .macLibraryEntryDraggable(item.id, selection: selection)
            .tag(item.id)
            .listRowInsets(.init(top: 4, leading: 8, bottom: 4, trailing: 8))
            .listRowSeparator(.visible)
            .listRowSeparatorTint(.white.opacity(0.06))
            .entryOpenInAlert(request: $openInRequest, entryID: item.id)
            .swipeActions(edge: .trailing) {
                EntryOpenInSwipeButton(entry: item.entry) { openInRequest = $0 }
                    .tint(.orange)

                Button("Delete", systemImage: "trash") {
                    actions.prepareDeletion(for: item.entry)
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                Button("Edit", systemImage: "pencil") {
                    editEntry(item.entry)
                }
                .tint(.blue)

                actions.shareButton(for: item.entry)
                    .tint(.indigo)
            }
        }

        private func editEntry(_ entry: AnimeEntry) {
            detailActions.edit(entry)
        }

        private func toggleFavorite(_ entry: AnimeEntry) {
            store.repository.toggleFavorite(entry)
        }
    }
#endif
