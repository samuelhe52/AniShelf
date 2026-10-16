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
    struct LibraryGridView: View {
        @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false
        @Environment(\.libraryEntryDetailActivation) private var detailActivation

        @Environment(LibraryStore.self) private var store
        @Environment(LibraryEntryInteractionState.self) private var interaction
        @Environment(LibraryEntryActionState.self) private var actions
        let detailActions: LibraryEntryDetailActions
        let displayItems: [LibraryEntryDisplayItem]
        @Binding var scrolledID: LibraryEntryIdentity?
        let scrollRequest: LibraryScrollRequest?
        let highlightRequest: LibraryHighlightRequest?
        /// Whether the trailing inspector is showing; the grid reflows smoothly when it changes.
        var isInspectorPresented = false
        private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 10)]

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(displayItems) { item in
                            configuredGridItem(for: item)
                                .geometryGroup()
                        }
                    }
                    .transaction(value: isInspectorPresented) { transaction in
                        transaction.animation = .smooth(duration: 0.3)
                    }
                    .onChange(of: scrollRequest) { handleScrollRequest(proxy: proxy) }
                    .onAppear { onGridViewAppear(proxy: proxy) }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 104)
                }
                .preferredNavigationBarScrollEdgeEffect()
                .animation(.spring, value: store.groupStrategy)
                .animation(.spring, value: store.sortReversed)
                .animation(.spring, value: store.sortStrategy)
                .animation(.spring, value: store.filters)
            }
        }

        private func handleScrollRequest(proxy: ScrollViewProxy) {
            guard let entryID = scrollRequest?.entryID else { return }
            withAnimation(.bouncy) {
                proxy.scrollTo(entryID)
            }
        }

        private func onGridViewAppear(proxy: ScrollViewProxy) {
            if let scrolledID {
                proxy.scrollTo(scrolledID, anchor: .center)
            }
        }

        private func configuredGridItem(for item: LibraryEntryDisplayItem) -> some View {
            LibraryGridItem(
                snapshot: item.snapshot,
                isSelected: !interaction.isMultiSelecting || interaction.isSelected(item.id)
            )
            .highlightEffect(trigger: highlightRequest?.trigger(for: item.id))
            .contextMenu {
                actions.contextMenu(
                    for: item.entry,
                    toggleFavorite: toggleFavorite,
                    editEntry: editEntry
                )
                .onAppear { scrolledID = item.id }
            } preview: {
                EntryContextMenuPreview(snapshot: item.snapshot)
                    .onAppear { scrolledID = item.id }
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
                    scrolledID = item.id
                    if interaction.isMultiSelecting {
                        toggleSelection(for: item.id)
                    } else {
                        openDetails(for: item.entry)
                    }
                },
                onFocusTap: {
                    scrolledID = item.id
                    interaction.focus(item.entry)
                    if interaction.isMultiSelecting {
                        toggleSelection(for: item.id)
                    }
                },
                onDoubleTap: {
                    openDetails(for: item.entry)
                    scrolledID = item.id
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
            displayItems: store.libraryDisplayItems,
            scrolledID: .constant(nil),
            scrollRequest: nil,
            highlightRequest: nil
        )
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(store)
        .environment(interaction)
        .environment(interaction.actions)
    }
#endif
