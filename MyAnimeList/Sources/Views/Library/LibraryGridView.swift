//
//  LibraryGridView.swift
//  MyAnimeList
//
//  Created by Samuel He on 7/27/25.
//

import DataProvider
import SwiftUI

struct LibraryGridView: View {
    @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false

    @Environment(LibraryStore.self) private var store
    @Environment(\.toggleFavorite) var toggleFavorite
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 10)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.libraryDisplayItems) { item in
                        configuredGridItem(for: item)
                    }
                }
                .onChange(of: scrolledID) { onChangeOfScrolledID(proxy: proxy) }
                .onAppear { onGridViewAppear(proxy: proxy) }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 104)
            }
            .animation(.spring, value: store.groupStrategy)
            .animation(.spring, value: store.sortReversed)
            .animation(.spring, value: store.sortStrategy)
            .animation(.spring, value: store.filters)
        }
        .libraryEntryInteractionOverlays(
            state: interaction,
            deleteEntry: { entry in
                store.deleteEntry(entry) { scrolledID = $0 }
            },
            detailRepository: store.repository
        )
    }

    private func onChangeOfScrolledID(proxy: ScrollViewProxy) {
        if let scrolledID {
            proxy.scrollTo(scrolledID)
        }
    }

    private func onGridViewAppear(proxy: ScrollViewProxy) {
        // Prevent the problem of programmatic scrolling doesn't work when images aren't loaded yet.
        if let scrolledID {
            proxy.scrollTo(scrolledID, anchor: .center)
        }
    }

    @ViewBuilder
    private func configuredGridItem(for item: LibraryEntryDisplayItem) -> some View {
        let baseItem = LibraryGridItem(snapshot: item.snapshot)
            .highlightEffect(
                showHighlight: interaction.highlightBinding(
                    for: item.id,
                    highlightedEntryID: $highlightedEntryID
                ),
                delay: 0.2
            )
            .contextMenu {
                interaction.contextMenu(
                    for: item.entry,
                    toggleFavorite: toggleFavorite
                )
                .onAppear { scrolledID = item.id }
            } preview: {
                EntryContextMenuPreview(snapshot: item.snapshot)
                    .onAppear { scrolledID = item.id }
            }

        if openDetailWithSingleTap {
            baseItem
                .onTapGesture {
                    scrolledID = item.id
                    interaction.detailingEntry = item.entry
                }
        } else {
            baseItem
                .onTapGesture { scrolledID = item.id }
                .onTapGesture(count: 2) {
                    interaction.detailingEntry = item.entry
                    scrolledID = item.id
                }
        }
    }
}

fileprivate struct LibraryGridItem: View {
    var snapshot: LibraryEntrySnapshot
    private let posterShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            poster
            titleLabel
        }
        .contentShape(.rect)
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { posterImage }
            .overlay(alignment: .topLeading) { statusIndicator }
            .overlay(alignment: .topTrailing) { favoriteIndicator }
            .overlay {
                posterShape
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(posterShape)
            .shadow(color: .black.opacity(0.22), radius: 11, y: 6)
    }

    private var posterImage: some View {
        KFImageView(
            url: snapshot.posterURL,
            targetWidth: 360,
            diskCacheExpiration: .longTerm
        )
        .scaledToFill()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleLabel: some View {
        Text(snapshot.title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.88))
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .lineSpacing(-1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
    }

    private var statusIndicator: some View {
        LibraryWatchStatusIndicator(
            status: snapshot.watchStatus,
            diameter: 10,
            strokeColor: .white.opacity(0.88),
            strokeWidth: 1.8,
            shadowColor: .black.opacity(0.22),
            shadowRadius: 4,
            shadowYOffset: 2
        )
        .padding(8)
    }

    @ViewBuilder
    private var favoriteIndicator: some View {
        if snapshot.isFavorite {
            LibraryFavoriteSymbol(
                isFavorite: true,
                font: .system(size: 11, weight: .bold),
                filledColor: .pink.opacity(0.92),
                emptyColor: .pink.opacity(0.92),
                shadowColor: .black.opacity(0.55),
                shadowRadius: 5,
                shadowYOffset: 2
            )
            .padding(8)
        }
    }
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryGridView(
        scrolledID: .constant(nil),
        highlightedEntryID: .constant(nil)
    )
    .onAppear {
        DataProvider.forPreview.generateEntriesForPreview()
    }
    .environment(store)
    .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
}
