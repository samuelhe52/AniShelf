//
//  MacBatchSelectionPanel.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// The inspector during a batch selection, as Finder's Get Info or a Keynote inspector
    /// shows several items: each property is a native control showing the shared value, or a
    /// mixed state, and changing it applies to every selected entry. The toolbar keeps its
    /// browsing controls, as Finder and Photos do with a selection.
    struct MacBatchSelectionPanel: View {
        let store: LibraryStore
        /// The selection in layout order.
        let selectedEntries: [AnimeEntry]
        /// The entry the last click selected, which goes on top of the stack.
        let lastClickedID: LibraryEntryIdentity?
        let scoringEnabled: Bool
        /// Applies an action to the given entries, which are all or one of the selection.
        let apply: ([AnimeEntry], LibraryBatchAction) -> Void
        let deleteSelectedEntries: () -> Void

        private static let posterLimit = 4
        /// The selection in the order it was made, oldest first, as of the last change.
        @State private var selectionOrder: [LibraryEntryIdentity] = []
        @State private var namePrompt: LibraryCategoryNamePrompt?

        var body: some View {
            Form {
                Section {
                    header
                }

                Section {
                    Picker("Status", selection: statusBinding) {
                        if statusBinding.wrappedValue == nil {
                            Text("Mixed").tag(AnimeEntry.WatchStatus?.none)
                        }
                        ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                            Text(status.localizedStringResource).tag(Optional(status))
                        }
                    }
                    if scoringEnabled {
                        Picker("Score", selection: scoreBinding) {
                            if scoreBinding.wrappedValue == .mixed {
                                Text("Mixed").tag(ScoreChoice.mixed)
                            }
                            Text("None").tag(ScoreChoice.unscored)
                            ForEach(Array(AnimeEntry.validScoreRange), id: \.self) { score in
                                Text(verbatim: "\(score)/5").tag(ScoreChoice.score(score))
                            }
                        }
                    }
                    Toggle("Favorite", sources: sources(\.favorite, action: LibraryBatchAction.favorite), isOn: \.self)
                    Toggle(
                        "Track Dates",
                        sources: sources(\.isDateTrackingEnabled, action: LibraryBatchAction.dateTracking),
                        isOn: \.self
                    )
                }

                if store.categoriesEnabled {
                    Section("Categories") {
                        ForEach(store.categories) { category in
                            Toggle(sources: categorySources(category.id), isOn: \.self) {
                                Text(verbatim: category.name)
                            }
                        }
                        Button("New Category…") {
                            namePrompt = .init(purpose: .create(memberCount: selectedEntries.count))
                        }
                    }
                }

                Section {
                    LibrarySelectionDeleteButton(
                        selectedEntries: selectedEntries,
                        deleteSelectedEntries: deleteSelectedEntries
                    )
                }
            }
            .formStyle(.grouped)
            .libraryCategoryNamePrompt($namePrompt) { _, name in
                guard let category = store.createCategory(named: name) else { return }
                apply(
                    selectedEntries,
                    .category(category.id, isMember: true, knownCategoryIDs: store.knownCategoryIDs)
                )
            }
            .onChange(of: selectedEntries.map(\.libraryIdentity), initial: true) {
                selectionOrder = currentOrder
            }
        }

        private var header: some View {
            VStack(spacing: 12) {
                posterStack
                VStack(spacing: 2) {
                    Text("\(selectedEntries.count) Selected")
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText(value: Double(selectedEntries.count)))
                        .animation(.snappy, value: selectedEntries.count)
                    Text(titleSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }

        // MARK: - Shared values

        /// The status every selected entry shares, or `nil` when they differ.
        private var statusBinding: Binding<AnimeEntry.WatchStatus?> {
            Binding(
                get: { sharedValue(\.watchStatus) },
                set: { status in
                    if let status { apply(selectedEntries, .watchStatus(status)) }
                }
            )
        }

        private enum ScoreChoice: Hashable {
            case mixed
            case unscored
            case score(Int)
        }

        private var scoreBinding: Binding<ScoreChoice> {
            Binding(
                get: {
                    guard let first = selectedEntries.first,
                        selectedEntries.allSatisfy({ $0.score == first.score })
                    else { return .mixed }
                    return first.score.map(ScoreChoice.score) ?? .unscored
                },
                set: { choice in
                    switch choice {
                    case .mixed: break
                    case .unscored: apply(selectedEntries, .score(nil))
                    case .score(let score): apply(selectedEntries, .score(score))
                    }
                }
            )
        }

        private func sharedValue<Value: Equatable>(_ keyPath: KeyPath<AnimeEntry, Value>) -> Value? {
            guard let first = selectedEntries.first?[keyPath: keyPath],
                selectedEntries.allSatisfy({ $0[keyPath: keyPath] == first })
            else { return nil }
            return first
        }

        /// One binding per selected entry, so a toggle shows the mixed state natively. Turning
        /// it on or off writes each entry through the same batch action.
        private func sources(
            _ keyPath: KeyPath<AnimeEntry, Bool>,
            action: @escaping (Bool) -> LibraryBatchAction
        ) -> [Binding<Bool>] {
            selectedEntries.map { entry in
                Binding(
                    get: { entry[keyPath: keyPath] },
                    set: { apply([entry], action($0)) }
                )
            }
        }

        private func categorySources(_ id: LibraryCategory.ID) -> [Binding<Bool>] {
            selectedEntries.map { entry in
                Binding(
                    get: { entry.categoryIDs.contains(id) },
                    set: { isMember in
                        apply([entry], .category(id, isMember: isMember, knownCategoryIDs: store.knownCategoryIDs))
                    }
                )
            }
        }

        /// The selection in the order entries joined it. Entries that join together, as with
        /// a ⇧-click range, keep their layout order, except that the clicked entry comes last.
        private var currentOrder: [LibraryEntryIdentity] {
            let ids = Set(selectedEntries.map(\.libraryIdentity))
            var order = selectionOrder.filter(ids.contains)
            let known = Set(order)
            var added = selectedEntries.map(\.libraryIdentity).filter { !known.contains($0) }
            if let lastClickedID, let index = added.firstIndex(of: lastClickedID) {
                added.append(added.remove(at: index))
            }
            order.append(contentsOf: added)
            return order
        }

        /// The most recently selected entries, newest first.
        private var newestEntries: [AnimeEntry] {
            let byID = Dictionary(
                selectedEntries.map { ($0.libraryIdentity, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return Array(currentOrder.reversed().compactMap { byID[$0] }.prefix(Self.posterLimit))
        }

        /// A stack of the newest posters: the latest selection lies flat on top, and older
        /// ones fan out behind it.
        private var posterStack: some View {
            let shown = newestEntries
            return ZStack {
                ForEach(Array(shown.enumerated()), id: \.element.libraryIdentity) { depth, entry in
                    let spread = CGFloat(depth)
                    // The grid's poster variant, which is usually still in the memory cache,
                    // so a newly selected poster is ready before its insertion animates.
                    KFImageView(
                        url: entry.selectedPosterPath.flatMap {
                            TMDbImageURLResolver.current.url(
                                for: $0, role: .poster, idealWidth: TMDbPosterDisplayType.grid.idealWidth)
                        },
                        targetWidth: 360,
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
                    .modifier(PosterFanStep(steps: spread))
                    // Count from the selection size, not the poster limit, so a deselected
                    // front poster stays above the one that takes its place while it leaves.
                    .zIndex(Double(selectedEntries.count - depth))
                    .transition(posterTransition(depth: depth))
                }
            }
            // Center the whole fan, rather than placing the front poster at the center
            // and leaving all the remaining visual weight on its left.
            .offset(x: CGFloat(max(shown.count - 1, 0)) * 7)
            .animation(.snappy(duration: 0.3), value: shown.map(\.libraryIdentity))
            .frame(height: 170)
            .accessibilityHidden(true)
        }

        /// The newest poster drops onto the pile and slides off it when deselected. Any other
        /// poster comes and goes one step further back in the fan, so a poster backfilling the
        /// stack, or pushed past its limit, moves through the back instead of popping in place.
        private func posterTransition(depth: Int) -> AnyTransition {
            let throughBack = AnyTransition.modifier(
                active: PosterFanStep(steps: 1),
                identity: PosterFanStep(steps: 0)
            ).combined(with: .opacity)
            guard depth == 0 else { return throughBack }
            return .asymmetric(
                insertion: .scale(scale: 1.15).combined(with: .opacity),
                removal: .offset(x: 36, y: -4).combined(with: .opacity)
            )
        }

        private var titleSummary: String {
            newestEntries.prefix(3).map(\.displayName).joined(separator: ", ")
        }
    }

    /// Moves a poster the given number of steps back in the fan: smaller, tilted further, and
    /// farther left and down.
    private struct PosterFanStep: ViewModifier {
        let steps: CGFloat

        func body(content: Content) -> some View {
            content
                .scaleEffect(1 - steps * 0.04)
                .rotationEffect(.degrees(Double(steps) * -3))
                .offset(x: -steps * 14, y: steps * 3)
        }
    }
#endif
