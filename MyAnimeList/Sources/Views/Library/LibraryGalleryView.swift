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
                        Text("The library is empty.")
                    }
            }
        }
        .libraryEntryInteractionOverlays(state: interaction, store: store)
    }

    private var libraryContent: some View {
        GeometryReader { geometry in
            let isHorizontal = geometry.size.width < geometry.size.height
            ScrollView(.horizontal) {
                LazyHStack {
                    ForEach(store.libraryOnDisplay, id: \.tmdbID) { entry in
                        AnimeEntryCardWrapper(
                            entry: entry,
                            store: store,
                            scrolledID: $scrolledID
                        )
                        .containerRelativeFrame(isHorizontal ? .horizontal : .vertical)
                        .onScrollVisibilityChange { _ in }
                    }
                }.scrollTargetLayout()
            }
            .scrollPosition(id: $scrolledID)
            .scrollTargetBehavior(.viewAligned)
        }
    }

}

fileprivate struct AnimeEntryCardWrapper: View {
    var entry: AnimeEntry
    let store: LibraryStore
    @Binding var scrolledID: Int?

    @Environment(LibraryEntryInteractionState.self) private var interaction
    @State private var imageLoaded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if imageLoaded {
                AnimeEntryDates(entry: entry)
            }
            AnimeEntryCard(entry: entry, imageLoaded: $imageLoaded)
                .contextMenu {
                    contextMenu(for: entry)
                }
        }
        .onTapGesture(count: 2) {
            interaction.detailingEntry = entry
            scrolledID = entry.tmdbID
        }
    }

    @ViewBuilder
    func contextMenu(for entry: AnimeEntry) -> some View {
        ControlGroup {
            Button("Edit", systemImage: "pencil") {
                interaction.setEditingEntry(entry)
            }
            Button("Share", systemImage: "square.and.arrow.up") {
                interaction.sharingAnimeEntry = entry
            }
        }
        Button {
            interaction.switchingPosterForEntry = entry
        } label: {
            Label("Switch Poster", systemImage: "photo.badge.magnifyingglass")
        }
        if let posterURL = entry.posterURL {
            ShareLink(item: posterURL) {
                Label("Save Poster", systemImage: "photo.badge.arrow.down")
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            interaction.prepareDeletion(for: entry, store: store, scrolledID: $scrolledID)
        }
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
