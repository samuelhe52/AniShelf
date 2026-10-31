//
//  LibraryGridView.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/27/25.
//

import DataProvider
import SwiftUI

// The Mac grid is `MacLibraryGrid`.
#if !os(macOS)
    import UIKit

    struct LibraryGridView: View {
        @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false
        @Environment(\.libraryEntryDetailActivation) private var detailActivation

        @Environment(LibraryStore.self) private var store
        @Environment(LibraryBrowseScope.self) private var scope
        @Environment(LibraryEntryInteractionState.self) private var interaction
        @Environment(LibraryEntryActionState.self) private var actions
        @State private var visibleEntries = LibraryVisibleEntryTracker()
        let detailActions: LibraryEntryDetailActions
        let displayItems: [LibraryEntryDisplayItem]
        let bookmark: LibraryScrollBookmark
        let scrollInputs: LibraryScrollInputs
        let highlightRequest: LibraryHighlightRequest?
        /// Whether the trailing inspector is showing; the grid reflows smoothly when it changes.
        var isInspectorPresented = false
        private var columns: [GridItem] {
            // Larger iPad cards spread column thresholds farther apart during window resizing.
            // Use device idiom so a narrow iPad window does not switch density at a size-class boundary.
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            return [GridItem(.adaptive(minimum: isPad ? 132 : 104, maximum: isPad ? 168 : 132), spacing: 10)]
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(displayItems) { item in
                            configuredGridItem(for: item)
                                .geometryGroup()
                        }
                    }
                    .scrollTargetLayout()
                    .transaction(value: isInspectorPresented) { transaction in
                        transaction.animation = .smooth(duration: 0.3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 104)
                }
                .onScrollTargetVisibilityChange(idType: LibraryEntryIdentity.self, threshold: 0.5) { ids in
                    visibleEntries.setVisible(ids, recordingInto: bookmark)
                }
                .libraryScrollBookmark(
                    bookmark,
                    tracker: visibleEntries,
                    displayIDs: displayItems.map(\.id),
                    inputs: scrollInputs,
                    proxy: proxy
                )
                // The reflow moves cards between rows; keep the entry the user was on.
                .onChange(of: isInspectorPresented) { bookmark.freeze() }
                .accessibilityIdentifier("library-grid")
                .preferredNavigationBarScrollEdgeEffect()
                .animation(.spring, value: scope.groupStrategy)
                .animation(.spring, value: scope.sortReversed)
                .animation(.spring, value: scope.sortStrategy)
                .animation(.spring, value: scope.filters)
            }
        }

        private func configuredGridItem(for item: LibraryEntryDisplayItem) -> some View {
            LibraryGridItem(
                snapshot: item.snapshot,
                isSelected: !interaction.isMultiSelecting || interaction.isSelected(item.id)
            )
            .accessibilityIdentifier("library-grid-item")
            .highlightEffect(trigger: highlightRequest?.trigger(for: item.id))
            .contextMenu {
                actions.contextMenu(
                    for: item.entry,
                    toggleFavorite: toggleFavorite,
                    editEntry: editEntry
                )
            } preview: {
                EntryContextMenuPreview(snapshot: item.snapshot)
            }
            .modifier(gestures(for: item))
        }

        private func gestures(for item: LibraryEntryDisplayItem) -> some ViewModifier {
            LibraryGridDetailGestureModifier(
                isMultiSelecting: interaction.isMultiSelecting,
                opensDetailOnSingleTap: detailActivation.usesSingleTap(
                    userPreference: openDetailWithSingleTap
                ),
                onPrimaryTap: {
                    if interaction.isMultiSelecting {
                        toggleSelection(for: item.id)
                    } else {
                        openDetails(for: item.entry)
                    }
                },
                onFocusTap: {
                    interaction.focus(item.entry)
                    if interaction.isMultiSelecting {
                        toggleSelection(for: item.id)
                    }
                },
                onDoubleTap: {
                    openDetails(for: item.entry)
                }
            )
        }

        private func toggleSelection(for id: LibraryEntryIdentity) {
            interaction.toggleSelection(for: id)
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

    fileprivate struct LibraryGridDetailGestureModifier: ViewModifier {
        let isMultiSelecting: Bool
        let opensDetailOnSingleTap: Bool
        let onPrimaryTap: () -> Void
        let onFocusTap: () -> Void
        let onDoubleTap: () -> Void

        func body(content: Content) -> some View {
            // Keep the card's recognizer tree stable when its detail host changes.
            // Swapping tap wrappers here recreates card-local image loading state.
            content
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isMultiSelecting || opensDetailOnSingleTap {
                            onPrimaryTap()
                        } else {
                            onFocusTap()
                        }
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard !isMultiSelecting, !opensDetailOnSingleTap else { return }
                        onDoubleTap()
                    }
                )
        }
    }

    #Preview {
        @Previewable let store = LibraryStore(dataProvider: .forPreview)
        @Previewable let interaction = LibraryEntryInteractionState()

        LibraryGridView(
            detailActions: LibraryEntryDetailActions(
                open: { _ in },
                edit: { _ in }
            ),
            displayItems: LibraryBrowseScope(store: store).displayItems,
            bookmark: LibraryScrollBookmark(),
            scrollInputs: LibraryScrollInputs(definition: LibraryBrowseScope(store: store).displayDefinition),
            highlightRequest: nil
        )
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(store)
        .environment(LibraryBrowseScope(store: store))
        .environment(interaction)
        .environment(interaction.actions)
    }
#endif
