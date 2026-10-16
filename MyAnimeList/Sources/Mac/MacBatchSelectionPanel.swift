//
//  MacBatchSelectionPanel.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// The inspector during a batch selection: the selection at a glance and its actions.
    /// The toolbar keeps its browsing controls, as Finder and Photos do with a selection,
    /// instead of switching to an edit mode with a Done button.
    struct MacBatchSelectionPanel: View {
        let store: LibraryStore
        let interaction: LibraryEntryInteractionState
        /// The selection in layout order.
        let selectedEntries: [AnimeEntry]
        /// The entry the last click selected, which goes on top of the stack.
        let lastClickedID: LibraryEntryIdentity?
        let entriesByID: [LibraryEntryIdentity: AnimeEntry]
        let scoringEnabled: Bool
        let applyBatchAction: (LibraryBatchAction) -> Void
        let deleteSelectedEntries: () -> Void
        let hideInspector: () -> Void

        private static let posterLimit = 4
        /// The selection in the order it was made, oldest first.
        @State private var selectionOrder: [LibraryEntryIdentity] = []
        // Update the visible collection in the same transaction as its order. Filtering
        // live selection here would remove a poster before the removal animation begins.
        @State private var newestEntries: [AnimeEntry] = []

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    posterStack
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(interaction.selectedEntryCount) Selected")
                            .font(.title2.weight(.bold))
                            .contentTransition(.numericText(value: Double(interaction.selectedEntryCount)))
                            .animation(.snappy, value: interaction.selectedEntryCount)
                        Text(titleSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    actionGroup {
                        LibrarySelectionStatusMenu(
                            interaction: interaction,
                            applyBatchAction: applyBatchAction,
                            presentation: .row
                        )
                        LibrarySelectionFavoriteButton(
                            interaction: interaction,
                            entriesByID: entriesByID,
                            applyBatchAction: applyBatchAction,
                            presentation: .row
                        )
                        if store.categoriesEnabled {
                            LibrarySelectionCategoryMenu(
                                store: store,
                                interaction: interaction,
                                entriesByID: entriesByID,
                                applyBatchAction: applyBatchAction,
                                presentation: .row
                            )
                        }
                        LibrarySelectionActionsMenu(
                            interaction: interaction,
                            scoringEnabled: scoringEnabled,
                            applyBatchAction: applyBatchAction,
                            presentation: .row
                        )
                    }

                    actionGroup {
                        LibrarySelectionDeleteButton(
                            interaction: interaction,
                            deleteSelectedEntries: deleteSelectedEntries,
                            presentation: .row
                        )
                    }
                }
                .padding(16)
            }
            .onChange(of: interaction.selectedEntryIDs, initial: true) { _, ids in
                updateSelectionOrder(ids)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Hide Inspector", systemImage: "sidebar.trailing", action: hideInspector)
                        .help(Text("Hide Inspector"))
                }
            }
        }

        /// Rows in one grouped box, as in a Mac inspector.
        private func actionGroup(@ViewBuilder rows: () -> some View) -> some View {
            VStack(spacing: 2) {
                rows()
            }
            .padding(4)
            .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        }

        /// Keeps entries in the order they joined the selection. Entries that join together,
        /// as with a ⇧-click range, keep their layout order, except that the clicked entry
        /// comes last.
        private func updateSelectionOrder(_ ids: Set<LibraryEntryIdentity>) {
            var order = selectionOrder.filter(ids.contains)
            let known = Set(order)
            var added = selectedEntries.map(\.libraryIdentity).filter { !known.contains($0) }
            if let lastClickedID, let index = added.firstIndex(of: lastClickedID) {
                added.append(added.remove(at: index))
            }
            order.append(contentsOf: added)
            let byID = Dictionary(
                selectedEntries.map { ($0.libraryIdentity, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            withAnimation(.snappy(duration: 0.3)) {
                selectionOrder = order
                newestEntries = Array(order.reversed().compactMap { byID[$0] }.prefix(Self.posterLimit))
            }
        }

        /// A stack of the newest posters: the latest selection lies flat on top, and older
        /// ones fan out behind it.
        private var posterStack: some View {
            let shown = newestEntries
            return ZStack {
                ForEach(Array(shown.enumerated()), id: \.element.libraryIdentity) { depth, entry in
                    let spread = CGFloat(depth)
                    KFImageView(
                        url: entry.posterURL,
                        targetSize: CGSize(width: 200, height: 300),
                        diskCacheExpiration: .longTerm
                    )
                    .scaledToFill()
                    .frame(width: 96, height: 144)
                    .background(.fill.tertiary)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(depth == 0 ? 0.20 : 0.10), radius: 3, y: 2)
                    .scaleEffect(1 - CGFloat(depth) * 0.04)
                    .rotationEffect(.degrees(Double(spread) * -3))
                    .offset(x: -spread * 14, y: spread * 3)
                    .zIndex(Double(Self.posterLimit - depth))
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 1.15).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                }
            }
            // Center the whole fan, rather than placing the front poster at the center
            // and leaving all the remaining visual weight on its left.
            .offset(x: CGFloat(max(shown.count - 1, 0)) * 7)
            .animation(.snappy(duration: 0.3), value: shown.map(\.libraryIdentity))
            .frame(height: 170)
            .accessibilityHidden(true)
        }

        private var titleSummary: String {
            newestEntries.prefix(3).map(\.displayName).joined(separator: ", ")
        }
    }
#endif
