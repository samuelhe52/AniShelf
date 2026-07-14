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
    @Binding var scrolledID: Int?
    @State private var localScrolledID: Int?
    let arrangement: LibraryPresentationPolicy.GalleryArrangement

    init(
        scrolledID: Binding<Int?>,
        arrangement: LibraryPresentationPolicy.GalleryArrangement = .singlePage
    ) {
        self._scrolledID = scrolledID
        self._localScrolledID = State(initialValue: scrolledID.wrappedValue)
        self.arrangement = arrangement
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
                        scrolledID: $scrolledID
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
        .scrollPosition(id: $localScrolledID)
        .scrollTargetBehavior(.viewAligned)
        .onChange(of: localScrolledID, initial: true) { _, entryID in
            guard let entryID,
                let entry = store.libraryDisplayItems.first(where: { $0.id == entryID })?.entry
            else { return }
            interaction.focus(entry)
        }
        .onChange(of: scrolledID) {
            guard localScrolledID != scrolledID else { return }
            localScrolledID = scrolledID
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

}

fileprivate struct AnimeEntryCardWrapper: View {
    var entry: AnimeEntry
    var snapshot: LibraryEntrySnapshot
    @Binding var scrolledID: Int?

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
                    interaction.openDetails(for: entry)
                    scrolledID = snapshot.id
                },
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
            interaction.editButton(for: entry)
            interaction.shareButton(for: entry)
        }
        interaction.switchPosterButton(for: entry)
        interaction.savePosterButton(for: entry)
        interaction.deleteButton(for: entry)
    }
}
