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
    @Environment(\.libraryEntryDetailActivation) private var detailActivation

    @Environment(LibraryStore.self) private var store
    @Environment(\.toggleFavorite) var toggleFavorite
    @Environment(LibraryEntryInteractionState.self) var interaction
    @Environment(\.libraryEntryOpenDetailAction) private var openDetailAction
    @Environment(\.libraryEntryEditAction) private var editAction
    let displayItems: [LibraryEntryDisplayItem]
    @Binding var scrolledID: Int?
    @Binding var highlightedEntryID: Int?
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 10)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(displayItems) { item in
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
    }

    private func onChangeOfScrolledID(proxy: ScrollViewProxy) {
        if let scrolledID {
            withAnimation(.bouncy) {
                proxy.scrollTo(scrolledID)
            }
        }
    }

    private func onGridViewAppear(proxy: ScrollViewProxy) {
        if let scrolledID {
            proxy.scrollTo(scrolledID, anchor: .center)
        }
    }

    @ViewBuilder
    private func configuredGridItem(for item: LibraryEntryDisplayItem) -> some View {
        let baseItem = LibraryGridItem(
            snapshot: item.snapshot,
            isSelected: !interaction.isMultiSelecting || interaction.isSelected(item.id)
        )
        .highlightEffect(
            showHighlight: interaction.highlightBinding(
                for: item.id,
                highlightedEntryID: $highlightedEntryID
            ),
            delay: 0.2
        )

        if detailActivation.usesSingleTap(userPreference: openDetailWithSingleTap) {
            baseItem
                .contextMenu {
                    interaction.contextMenu(
                        for: item.entry,
                        toggleFavorite: toggleFavorite,
                        editEntry: editEntry
                    )
                    .onAppear { scrolledID = item.id }
                } preview: {
                    EntryContextMenuPreview(snapshot: item.snapshot)
                        .onAppear { scrolledID = item.id }
                }
                .onTapGesture {
                    scrolledID = item.id
                    if interaction.isMultiSelecting {
                        toggleSelection(for: item.id)
                    } else {
                        openDetails(for: item.entry)
                    }

                }
        } else {
            gridItemWithDoubleTapDetail(baseItem: baseItem, item: item)
        }
    }

    private func gridItemWithDoubleTapDetail(
        baseItem: some View,
        item: LibraryEntryDisplayItem
    ) -> some View {
        baseItem
            .contextMenu {
                interaction.contextMenu(
                    for: item.entry,
                    toggleFavorite: toggleFavorite,
                    editEntry: editEntry
                )
                .onAppear { scrolledID = item.id }
            } preview: {
                EntryContextMenuPreview(snapshot: item.snapshot)
                    .onAppear { scrolledID = item.id }
            }
            .modifier(
                LibraryGridDoubleTapOpenModifier(
                    isMultiSelecting: interaction.isMultiSelecting,
                    onSingleTap: {
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
            )
    }

    private func toggleSelection(for id: Int) {
        interaction.toggleSelection(for: id)
    }

    private func openDetails(for entry: AnimeEntry) {
        if let openDetailAction {
            openDetailAction(entry)
        } else {
            interaction.openDetails(for: entry)
        }
    }

    private func editEntry(_ entry: AnimeEntry) {
        if let editAction {
            editAction(entry)
        } else {
            interaction.setEditingEntry(entry)
        }
    }
}

fileprivate struct LibraryGridDoubleTapOpenModifier: ViewModifier {
    let isMultiSelecting: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void

    func body(content: Content) -> some View {
        if isMultiSelecting {
            content.onTapGesture(perform: onSingleTap)
        } else {
            // Recognize focus immediately while reserving detail opening for two taps.
            content
                .simultaneousGesture(
                    TapGesture().onEnded { onSingleTap() }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { onDoubleTap() }
                )
        }
    }
}

fileprivate struct LibraryGridItem: View {
    var snapshot: LibraryEntrySnapshot
    var isSelected: Bool = true
    private let posterShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            poster
            titleLabel
        }
        .opacity(selectionOpacity)
        .scaleEffect(selectionScale)
        .contentShape(.rect)
        .animation(.bouncy(duration: 0.18, extraBounce: 0.1), value: isSelected)
    }

    private var poster: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { posterImage }
            .overlay(alignment: .topLeading) { statusIndicator }
            .overlay(alignment: .topTrailing) { favoriteIndicator }
            .overlay(alignment: .bottom) { progressBar }
            .overlay {
                posterShape
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(posterShape)
            .shadow(color: .black.opacity(0.22), radius: 11, y: 6)
    }

    private var posterImage: some View {
        KFImageView(
            url: snapshot.displayPosterURL(for: .grid),
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

    private var progressBar: some View {
        LibraryPosterEpisodeProgressBar(
            fractionCompleted: snapshot.episodeProgressFraction,
            style: .compact
        )
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

    private var selectionOpacity: Double {
        isSelected ? 1 : 0.48
    }

    private var selectionScale: CGFloat {
        isSelected ? 1 : 0.95
    }
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryGridView(
        displayItems: store.libraryDisplayItems,
        scrolledID: .constant(nil),
        highlightedEntryID: .constant(nil)
    )
    .onAppear {
        DataProvider.forPreview.generateEntriesForPreview()
    }
    .environment(store)
    .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
}
