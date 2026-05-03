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
    let store: LibraryStore
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Binding var scrolledID: Int?

    var body: some View {
        Group {
            if !store.libraryOnDisplay.isEmpty {
                libraryContent
            } else {
                Color.clear
                    .overlay {
                        Text(emptyLibraryResource)
                    }
            }
        }
        .libraryEntryInteractionOverlays(state: interaction, store: store)
    }

    private var libraryContent: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(store.libraryOnDisplay, id: \.tmdbID) { entry in
                        AnimeEntryCardWrapper(
                            entry: entry,
                            store: store,
                            scrolledID: $scrolledID
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onScrollVisibilityChange { _ in }
                    }
                }
                .scrollTargetLayout()
            }
            .animation(.default, value: store.filters)
            .scrollClipDisabled()
            .scrollPosition(id: $scrolledID)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var emptyLibraryResource: LocalizedStringResource {
        "The library is empty."
    }

}

fileprivate struct AnimeEntryCardWrapper: View {
    var entry: AnimeEntry
    let store: LibraryStore
    @Binding var scrolledID: Int?

    @Environment(LibraryEntryInteractionState.self) private var interaction
    @State private var imageLoaded: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            if imageLoaded {
                AnimeEntryDates(entry: entry)
            }
            AnimeEntryCard(
                entry: entry,
                onOpenDetails: {
                    interaction.detailingEntry = entry
                    scrolledID = entry.tmdbID
                },
                imageLoaded: $imageLoaded
            )
            .contextMenu {
                contextMenu(for: entry)
                    .onAppear { scrolledID = entry.tmdbID }
            } preview: {
                EntryContextMenuPreview(entry: entry)
                    .onAppear { scrolledID = entry.tmdbID }
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
        interaction.deleteButton(for: entry, store: store, scrolledID: $scrolledID)
    }
}

#if DEBUG
    // This is where we place debug-specific code.
    extension LibraryGalleryView {
        private func mockDelete(entry: AnimeEntry) {
            store.mockDeleteEntry(entry)
        }
    }
#endif
