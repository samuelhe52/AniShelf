//
//  MacLibraryGrid.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// The Mac library grid. `LazyVGrid` has no selection API, so clicks and arrow keys go
    /// through the window's `MacLibrarySelection`. The iOS grid is `LibraryGridView`.
    struct MacLibraryGrid: View {
        @Environment(\.macLibraryInspectorLayout) private var inspectorLayout
        @Environment(LibraryStore.self) private var store
        @Environment(LibraryEntryActionState.self) private var actions
        @Environment(MacLibrarySelection.self) private var selection
        let detailActions: LibraryEntryDetailActions
        let displayItems: [LibraryEntryDisplayItem]
        @Binding var scrolledID: LibraryEntryIdentity?
        let scrollRequest: LibraryScrollRequest?
        let highlightRequest: LibraryHighlightRequest?
        /// Whether the trailing inspector is showing; the grid reflows smoothly when it changes.
        var isInspectorPresented = false

        nonisolated private static let minimumColumnWidth: CGFloat = 132
        nonisolated private static let columnSpacing: CGFloat = 18
        private let columns = [
            GridItem(.adaptive(minimum: minimumColumnWidth, maximum: 168), spacing: columnSpacing)
        ]
        @FocusState private var isGridFocused: Bool
        @State private var columnCount = 1

        var body: some View {
            GeometryReader { visibleViewport in
                GeometryReader { viewport in
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(displayItems) { item in
                                    configuredGridItem(for: item)
                                        .geometryGroup()
                                }
                            }
                            .transaction(value: hasInspectorInset) { transaction in
                                transaction.animation = .smooth(duration: 0.3)
                            }
                            .onChange(of: scrollRequest) { handleScrollRequest(proxy: proxy) }
                            .onAppear { onGridViewAppear(proxy: proxy) }
                            .onGeometryChange(for: Int.self) { geometry in
                                Self.columnCount(forWidth: geometry.size.width)
                            } action: {
                                columnCount = $0
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                            .padding(.bottom, 104)
                            .frame(width: max(0, viewport.size.width - inspectorInset))
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: max(0, visibleViewport.size.width), alignment: .leading)
                        // Layout the grid at its destination, while the native safe area controls
                        // the visible scroll viewport. Do not animate either sizing proposal.
                        .transaction(value: hasInspectorInset) { $0.animation = nil }
                        .preferredNavigationBarScrollEdgeEffect()
                        .animation(.spring, value: store.groupStrategy)
                        .animation(.spring, value: store.sortReversed)
                        .animation(.spring, value: store.sortStrategy)
                        .animation(.spring, value: store.filters)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($isGridFocused)
                        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                            moveSelection(press.key, proxy: proxy) ? .handled : .ignored
                        }
                        .onExitCommand { selection.select([]) }
                    }
                }
                // The native inspector animates the trailing safe area through every width.
                // Its full content width supplies our one destination instead.
                .ignoresSafeArea(.container, edges: .trailing)
            }
        }

        private var hasInspectorInset: Bool {
            isInspectorPresented && inspectorLayout?.width != nil
        }

        private var inspectorInset: CGFloat {
            hasInspectorInset ? inspectorLayout?.width ?? 0 : 0
        }

        /// The number of columns an adaptive grid item fits into this width.
        nonisolated private static func columnCount(forWidth width: CGFloat) -> Int {
            max(1, Int((width + columnSpacing) / (minimumColumnWidth + columnSpacing)))
        }

        /// Arrow keys move the selection by one card, or by one row vertically.
        private func moveSelection(_ key: KeyEquivalent, proxy: ScrollViewProxy) -> Bool {
            guard !displayItems.isEmpty else { return false }
            let offset =
                switch key {
                case .leftArrow: -1
                case .rightArrow: 1
                case .upArrow: -columnCount
                default: columnCount
                }
            // At an edge the key is still consumed so the scroll view does not jump.
            if let id = selection.move(by: offset, in: displayItems.map(\.id)) {
                scrolledID = id
                proxy.scrollTo(id)
            }
            return true
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
            // Desktop selection marks the chosen cards instead of dimming the others.
            LibraryGridItem(
                snapshot: item.snapshot,
                showsSelectionRing: selection.ids.contains(item.id)
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
            .modifier(
                MacLibraryGridClickModifier(
                    onClick: {
                        isGridFocused = true
                        scrolledID = item.id
                        selection.click(item.id, .current, layoutIDs: displayItems.map(\.id))
                    },
                    onDoubleClick: {
                        scrolledID = item.id
                        detailActions.open(item.entry)
                    }
                )
            )
        }

        private func editEntry(_ entry: AnimeEntry) {
            detailActions.edit(entry)
        }

        private func toggleFavorite(_ entry: AnimeEntry) {
            store.repository.toggleFavorite(entry)
        }
    }

    fileprivate struct MacLibraryGridClickModifier: ViewModifier {
        let onClick: () -> Void
        let onDoubleClick: () -> Void

        func body(content: Content) -> some View {
            content
                .simultaneousGesture(TapGesture().onEnded(onClick))
                .simultaneousGesture(TapGesture(count: 2).onEnded(onDoubleClick))
        }
    }

    #Preview {
        @Previewable let store = LibraryStore(dataProvider: .forPreview)

        MacLibraryGrid(
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
        .environment(LibraryEntryActionState())
        .environment(MacLibrarySelection())
    }
#endif
