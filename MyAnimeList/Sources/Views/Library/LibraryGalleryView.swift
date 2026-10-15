//
//  LibraryGalleryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/25.
//

import DataProvider
import Foundation
import SwiftUI

struct LibraryGalleryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var scrolledID: LibraryEntryIdentity?
    let scrollRequest: LibraryScrollRequest?
    let detailActions: LibraryEntryDetailActions
    @State private var localScrolledID: LibraryEntryIdentity?
    #if os(macOS)
        @State private var isHoveringShelf = false
    #endif

    init(
        scrolledID: Binding<LibraryEntryIdentity?>,
        scrollRequest: LibraryScrollRequest?,
        detailActions: LibraryEntryDetailActions
    ) {
        self._scrolledID = scrolledID
        self.scrollRequest = scrollRequest
        self.detailActions = detailActions
        self._localScrolledID = State(initialValue: scrolledID.wrappedValue)
    }

    var body: some View {
        Group {
            if !store.libraryDisplayItems.isEmpty {
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
                ForEach(store.libraryDisplayItems) { item in
                    AnimeEntryCardWrapper(
                        entry: item.entry,
                        snapshot: item.snapshot,
                        scrolledID: $scrolledID,
                        detailActions: detailActions,
                        onToggleFavorite: toggleFavorite
                    )
                    .frame(width: itemWidth, height: height)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, horizontalContentMargin, for: .scrollContent)
        .animation(.default, value: store.groupStrategy)
        .animation(.default, value: store.sortReversed)
        .animation(.default, value: store.sortStrategy)
        .animation(.default, value: store.filters)
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
        #if os(macOS)
            .overlay {
                MacGalleryPager(
                    itemIDs: store.libraryDisplayItems.map(\.id),
                    currentID: $localScrolledID,
                    trailingInset: interaction.inspectorPresentation != nil ? 36 : 0,
                    isVisible: isHoveringShelf
                )
            }
            .onHover { isHoveringShelf = $0 }
        #endif
        .scrollPosition(id: $localScrolledID)
        .scrollTargetBehavior(.viewAligned)
        .onChange(of: localScrolledID, initial: true) { _, entryID in
            guard let entryID,
                let entry = store.libraryDisplayItems.first(where: { $0.id == entryID })?.entry
            else { return }
            interaction.focus(entry)
        }
        .onChange(of: scrollRequest) {
            guard localScrolledID != scrollRequest?.entryID else { return }
            localScrolledID = scrollRequest?.entryID
        }
        .onScrollPhaseChange { _, newPhase in
            if !newPhase.isScrolling {
                commitLocalScrollPosition()
            }
        }
        .onDisappear {
            commitLocalScrollPosition()
        }
    }

    private func commitLocalScrollPosition() {
        guard scrolledID != localScrolledID else { return }
        scrolledID = localScrolledID
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
    @Binding var scrolledID: LibraryEntryIdentity?
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
                onOpenDetails: {
                    openDetails()
                    scrolledID = snapshot.id
                },
                onToggleFavorite: onToggleFavorite,
                imageLoaded: $imageLoaded
            )
            .contextMenu {
                contextMenu(for: entry)
                    .onAppear { scrolledID = snapshot.id }
            } preview: {
                EntryContextMenuPreview(snapshot: snapshot)
                    .onAppear { scrolledID = snapshot.id }
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
            interaction.editButton(for: entry, editEntry: editEntry)
            interaction.shareButton(for: entry)
        }
        interaction.switchPosterButton(for: entry)
        interaction.savePosterButton(for: entry)
        interaction.deleteButton(for: entry)
    }

    private func openDetails() {
        detailActions.open(entry)
    }

    private func editEntry(_ entry: AnimeEntry) {
        detailActions.edit(entry)
    }
}

#if os(macOS)
    /// Desktop paging for the horizontal shelf: a mouse wheel cannot scroll it sideways,
    /// so hover buttons and the arrow keys step one card at a time.
    fileprivate struct MacGalleryPager: View {
        let itemIDs: [LibraryEntryIdentity]
        @Binding var currentID: LibraryEntryIdentity?
        var trailingInset: CGFloat = 0
        /// Whether the pointer is over the shelf; the buttons only show then.
        var isVisible: Bool

        @FocusState private var isFocused: Bool

        var body: some View {
            HStack {
                pageButton(offset: -1, systemImage: "chevron.left", label: "Previous")
                Spacer()
                pageButton(offset: 1, systemImage: "chevron.right", label: "Next")
            }
            .padding(.leading, 16)
            .padding(.trailing, 16 + trailingInset)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: isVisible)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(.leftArrow) { step(by: -1) ? .handled : .ignored }
            .onKeyPress(.rightArrow) { step(by: 1) ? .handled : .ignored }
            .onAppear { isFocused = true }
        }

        private func pageButton(offset: Int, systemImage: String, label: LocalizedStringResource) -> some View {
            Button {
                step(by: offset)
            } label: {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(target(by: offset) == nil)
            .accessibilityLabel(Text(label))
        }

        private func target(by offset: Int) -> LibraryEntryIdentity? {
            guard !itemIDs.isEmpty else { return nil }
            let index = currentID.flatMap { itemIDs.firstIndex(of: $0) } ?? 0
            let targetIndex = index + offset
            guard itemIDs.indices.contains(targetIndex) else { return nil }
            return itemIDs[targetIndex]
        }

        @discardableResult
        private func step(by offset: Int) -> Bool {
            guard let id = target(by: offset) else { return false }
            withAnimation(.snappy) { currentID = id }
            return true
        }
    }
#endif
