//
//  LibraryListView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/29.
//

import DataProvider
import SwiftUI

// The Mac list is `MacLibraryList`.
#if !os(macOS)
    struct LibraryListView: View {
        @Environment(LibraryStore.self) private var store
        @Environment(LibraryBrowseScope.self) private var scope
        @Environment(LibraryEntryInteractionState.self) private var interaction
        @Environment(LibraryEntryActionState.self) private var actions
        @State private var openInRequest: EntryOpenInRequest?

        let detailActions: LibraryEntryDetailActions
        let displayItems: [LibraryEntryDisplayItem]
        @Binding var scrolledID: LibraryEntryIdentity?
        let scrollRequest: LibraryScrollRequest?
        let highlightRequest: LibraryHighlightRequest?

        var body: some View {
            ScrollViewReader { proxy in
                List(
                    displayItems,
                    selection: listSelection
                ) { item in
                    rowContent(for: item)
                }
                .listStyle(.plain)
                .accessibilityIdentifier("library-list")
                .preferredNavigationBarScrollEdgeEffect()
                .environment(\.editMode, .constant(interaction.isMultiSelecting ? .active : .inactive))
                .animation(LibraryViewTransitions.selectionModeAnimation(), value: interaction.isMultiSelecting)
                .animation(.default, value: scope.groupStrategy)
                .animation(.default, value: scope.sortReversed)
                .animation(.default, value: scope.sortStrategy)
                .animation(.default, value: scope.filters)
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

        @ViewBuilder
        private func rowContent(for item: LibraryEntryDisplayItem) -> some View {
            AnimeEntryListRow(
                entry: item.entry,
                snapshot: item.snapshot,
                // Masked, not removed, so edit-mode taps reach the List's selection.
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
                value: !interaction.isMultiSelecting || interaction.isSelected(item.id)
            )
            .highlightEffect(trigger: highlightRequest?.trigger(for: item.id))
            .tag(item.id)
            .listRowInsets(.init(top: 8, leading: 10, bottom: 8, trailing: 10))
            .listRowSeparator(.visible)
            .listRowSeparatorTint(.white.opacity(0.06))
            .listRowBackground(Color.clear)
            .contextMenu {
                actions.contextMenu(
                    for: item.entry,
                    toggleFavorite: toggleFavorite,
                    editEntry: editEntry
                )
            } preview: {
                EntryContextMenuPreview(snapshot: item.snapshot)
                    .onAppear { scrolledID = item.id }
            }
            .entryOpenInAlert(request: $openInRequest, entryID: item.id)
            .swipeActions(edge: .trailing) {
                if !interaction.isMultiSelecting {
                    EntryOpenInSwipeButton(entry: item.entry) { openInRequest = $0 }
                        .tint(.orange)

                    Button("Delete", systemImage: "trash") {
                        actions.prepareDeletion(for: item.entry)
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

                    actions.shareButton(for: item.entry)
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
#endif
