//
//  LibraryGalleryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/25.
//

import DataProvider
import Foundation
import SwiftUI

// The Mac has no Gallery; see `MacLibraryView.libraryViewStyle`.
#if !os(macOS)
    struct LibraryGalleryView: View {
        @Environment(LibraryStore.self) private var store
        @Environment(LibraryBrowseScope.self) private var scope
        @Environment(LibraryEntryInteractionState.self) var interaction
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let bookmark: LibraryScrollBookmark
        let scrollInputs: LibraryScrollInputs
        let detailActions: LibraryEntryDetailActions
        /// The aligned card; the gallery's own position, which the bookmark follows.
        @State private var currentEntryID: LibraryEntryIdentity?

        init(
            bookmark: LibraryScrollBookmark,
            scrollInputs: LibraryScrollInputs,
            displayIDs: [LibraryEntryIdentity],
            detailActions: LibraryEntryDetailActions
        ) {
            self.bookmark = bookmark
            self.scrollInputs = scrollInputs
            self.detailActions = detailActions
            // Start on the bookmarked card, so the first frame does not show the first one.
            self._currentEntryID = State(initialValue: bookmark.target(in: displayIDs))
        }

        var body: some View {
            Group {
                if !scope.displayItems.isEmpty {
                    libraryContent
                } else {
                    Color.clear
                        .overlay {
                            Text(emptyLibraryResource)
                        }
                }
            }
        }

        private var libraryContent: some View {
            GeometryReader { geometry in
                let arrangement = LibraryGalleryLayoutPolicy().arrangement(
                    for:
                        .init(
                            availableSize: geometry.size,
                            dynamicTypeSize: dynamicTypeSize
                        )
                )

                switch arrangement {
                case .singlePage:
                    galleryScroll(
                        itemWidth: geometry.size.width,
                        itemSpacing: 0,
                        horizontalContentMargin: 0,
                        height: geometry.size.height
                    )
                case .shelf(let cardWidth):
                    let itemWidth = min(cardWidth + 52, geometry.size.width)
                    galleryScroll(
                        itemWidth: itemWidth,
                        itemSpacing: 12,
                        horizontalContentMargin: max((geometry.size.width - itemWidth) / 2, 20),
                        height: geometry.size.height
                    )
                }
            }
        }

        private func galleryScroll(
            itemWidth: CGFloat,
            itemSpacing: CGFloat,
            horizontalContentMargin: CGFloat,
            height: CGFloat
        ) -> some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: itemSpacing) {
                    ForEach(scope.displayItems) { item in
                        AnimeEntryCardWrapper(
                            entry: item.entry,
                            snapshot: item.snapshot,
                            detailActions: detailActions,
                            onToggleFavorite: toggleFavorite
                        )
                        .frame(width: itemWidth, height: height)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, horizontalContentMargin, for: .scrollContent)
            .accessibilityIdentifier("library-gallery")
            .animation(.default, value: scope.groupStrategy)
            .animation(.default, value: scope.sortReversed)
            .animation(.default, value: scope.sortStrategy)
            .animation(.default, value: scope.filters)
            .scrollClipDisabled()
            .overlay(alignment: .trailing) {
                if interaction.inspectorPresentation != nil {
                    LinearGradient(
                        colors: [.clear, Color.platformSystemBackground],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .scrollPosition(id: $currentEntryID)
            .scrollTargetBehavior(.viewAligned)
            // Hold the restored card until the user swipes.
            .onAppear { bookmark.settle(on: currentEntryID, order: scope.displayIDs) }
            .onChange(of: currentEntryID, initial: true) { _, entryID in
                guard let entryID,
                    let entry = scope.displayItems.first(where: { $0.id == entryID })?.entry
                else { return }
                bookmark.record(entryID, order: scope.displayIDs)
                interaction.focus(entry)
            }
            // One handler for both, so a jump that also leaves a category goes to its entry.
            .onChange(of: scrollInputs) { old, new in
                let target = new.request != old.request ? new.request?.entryID : scope.displayIDs.first
                guard let target, target != currentEntryID else { return }
                bookmark.settle(on: target, order: scope.displayIDs)
                currentEntryID = target
            }
            // When the aligned card is deleted or leaves the list, align its nearest neighbor.
            // Settle rather than record: a restore may still hold the bookmark, and a held
            // bookmark left on the removed card would restore elsewhere after a second removal.
            .onChange(of: scope.displayIDs) { old, new in
                guard let currentEntryID, !new.contains(currentEntryID) else { return }
                let neighbor = LibraryScrollBookmark.nearest(to: currentEntryID, in: old, surviving: new)
                bookmark.settle(on: neighbor, order: new)
                self.currentEntryID = neighbor
            }
            .onScrollPhaseChange { _, phase in
                if phase.isUserScroll { bookmark.userDidScroll() }
            }
        }

        private var emptyLibraryResource: LocalizedStringResource {
            "The library is empty."
        }

        private func toggleFavorite(_ entry: AnimeEntry) {
            store.repository.toggleFavorite(entry)
        }

    }

    fileprivate struct AnimeEntryCardWrapper: View {
        var entry: AnimeEntry
        var snapshot: LibraryEntrySnapshot
        let detailActions: LibraryEntryDetailActions
        let onToggleFavorite: (AnimeEntry) -> Void

        @Environment(LibraryEntryInteractionState.self) private var interaction
        @State private var imageLoaded: Bool = false

        var body: some View {
            VStack(spacing: 14) {
                if imageLoaded {
                    AnimeEntryDates(snapshot: snapshot)
                }
                AnimeEntryCard(
                    entry: entry,
                    snapshot: snapshot,
                    onOpenDetails: openDetails,
                    onToggleFavorite: onToggleFavorite,
                    imageLoaded: $imageLoaded
                )
                .contextMenu {
                    contextMenu(for: entry)
                } preview: {
                    EntryContextMenuPreview(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        @ViewBuilder
        func contextMenu(for entry: AnimeEntry) -> some View {
            ControlGroup {
                interaction.actions.editButton(for: entry, editEntry: editEntry)
                interaction.actions.shareButton(for: entry)
            }
            interaction.actions.categoriesMenu(for: entry)
            interaction.actions.switchPosterButton(for: entry)
            interaction.actions.savePosterButton(for: entry)
            interaction.actions.deleteButton(for: entry)
        }

        private func openDetails() {
            detailActions.open(entry)
        }

        private func editEntry(_ entry: AnimeEntry) {
            detailActions.edit(entry)
        }
    }
#endif
