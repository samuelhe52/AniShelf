//
//  LibraryGridView.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/27/25.
//

import DataProvider
import SwiftUI

struct LibraryGridView: View {
    let store: LibraryStore
    @Environment(\.toggleFavorite) var toggleFavorite
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))]) {
                    ForEach(store.libraryOnDisplay, id: \.tmdbID) { entry in
                        LibraryGridItem(entry: entry)
                            .highlightEffect(
                                showHighlight: interaction.highlightBinding(
                                    for: entry,
                                    highlightedEntryID: $highlightedEntryID
                                ),
                                delay: 0.2
                            )
                            .contextMenu {
                                interaction.contextMenu(
                                    for: entry,
                                    store: store,
                                    scrolledID: $scrolledID,
                                    toggleFavorite: toggleFavorite
                                )
                                .onAppear { scrolledID = entry.tmdbID }
                            } preview: {
                                EntryContextMenuPreview(entry: entry)
                                    .onAppear { scrolledID = entry.tmdbID }
                            }
                            .onTapGesture { scrolledID = entry.tmdbID }
                            .onTapGesture(count: 2) {
                                interaction.detailingEntry = entry
                                scrolledID = entry.tmdbID
                            }
                    }
                }
                .onChange(of: scrolledID) { onChangeOfScrolledID(proxy: proxy) }
                .onAppear { onGridViewAppear(proxy: proxy) }
                .padding(.horizontal)
            }
            .animation(.spring, value: store.sortReversed)
            .animation(.spring, value: store.sortStrategy)
            .animation(.spring, value: store.filters)
        }
        .libraryEntryInteractionOverlays(state: interaction, store: store)
    }

    private func onChangeOfScrolledID(proxy: ScrollViewProxy) {
        if let scrolledID {
            withAnimation {
                proxy.scrollTo(scrolledID)
            }
        }
    }

    private func onGridViewAppear(proxy: ScrollViewProxy) {
        // Prevent the problem of programmatic scrolling doesn't work when images aren't loaded yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let scrolledID {
                withAnimation {
                    proxy.scrollTo(scrolledID, anchor: .center)
                }
            }
        }
    }
}

fileprivate struct LibraryGridItem: View {
    var entry: AnimeEntry

    var body: some View {
        VStack {
            KFImageView(url: entry.posterURL, targetWidth: 300, diskCacheExpiration: .longTerm)
                .clipShape(.proportionalRounded(cornerFraction: 0.05))
                .aspectRatio(contentMode: .fit)
            Text(entry.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#Preview {
    LibraryGridView(
        store: LibraryStore(dataProvider: .forPreview),
        scrolledID: .constant(nil),
        highlightedEntryID: .constant(nil)
    )
    .onAppear {
        DataProvider.forPreview.generateEntriesForPreview()
    }
    .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
}
