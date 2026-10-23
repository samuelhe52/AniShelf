//
//  LibraryBrowseScope.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/18.
//

import DataProvider
import Foundation
import SwiftUI

/// One window's view of the library: its filters, category, sort, group, and view style, and
/// the filtered, sorted display list they produce (docs-ai 028).
///
/// The library itself, categories, and preferences stay in `LibraryStore`. Sort, group, and
/// view style changes also write the preference, so the latest choice seeds the next new
/// window, but a preference change from elsewhere never rewrites an open window.
@Observable @MainActor
final class LibraryBrowseScope {
    /// The persisted form, saved per scene.
    struct State: Codable, Equatable {
        var filterIDs: [String]
        var activeCategoryID: LibraryCategory.ID?
        var sortStrategy: LibraryStore.AnimeSortStrategy
        var sortReversed: Bool
        var groupStrategy: LibraryStore.LibraryGroupStrategy
        var viewStyle: LibraryViewStyle
    }

    @ObservationIgnored let store: LibraryStore

    var filters: Set<LibraryStore.AnimeFilter>
    /// The category this window is narrowed to; `nil` means All.
    ///
    /// Reads as `nil` while categories are disabled or after the category was deleted.
    var activeCategoryID: LibraryCategory.ID? {
        get {
            guard store.categoriesEnabled, let storedCategoryID,
                store.categories.contains(where: { $0.id == storedCategoryID })
            else { return nil }
            return storedCategoryID
        }
        set { storedCategoryID = newValue }
    }
    private var storedCategoryID: LibraryCategory.ID?
    var sortStrategy: LibraryStore.AnimeSortStrategy {
        didSet {
            guard !isRestoring, store.sortStrategy != sortStrategy else { return }
            store.sortStrategy = sortStrategy
        }
    }
    var sortReversed: Bool {
        didSet {
            guard !isRestoring, store.sortReversed != sortReversed else { return }
            store.sortReversed = sortReversed
        }
    }
    var groupStrategy: LibraryStore.LibraryGroupStrategy {
        didSet {
            guard !isRestoring, store.groupStrategy != groupStrategy else { return }
            store.groupStrategy = groupStrategy
        }
    }
    var viewStyle: LibraryViewStyle {
        didSet {
            guard !isRestoring else { return }
            Self.saveViewStylePreference(viewStyle)
        }
    }
    /// Set while restored scene state is applied, which must not overwrite the preferences
    /// that seed new windows.
    @ObservationIgnored private var isRestoring = false
    /// Whether scene state restored after the window appeared may still replace this scope.
    ///
    /// Cleared for good by the first change that is not a restoration, so a late value never
    /// overwrites the user's own browsing.
    @ObservationIgnored var acceptsSceneRestoration = true

    /// Bumped when the cached display list goes stale, so views reading it re-render.
    private var displayGeneration = 0
    @ObservationIgnored private var displayCache: LibraryDisplayCache?
    @ObservationIgnored private var isInvalidatingDisplay = false
    /// How many times the display list was computed; tests use it to catch spurious invalidation.
    @ObservationIgnored private(set) var displayComputeCount = 0

    /// Restores `state` when given, otherwise seeds from the store's preferences.
    init(store: LibraryStore, restoring state: State? = nil) {
        self.store = store
        let state = state ?? Self.seedState(from: store)
        filters = Self.filters(from: state)
        storedCategoryID = state.activeCategoryID
        sortStrategy = state.sortStrategy
        sortReversed = state.sortReversed
        groupStrategy = Self.groupStrategy(from: state)
        viewStyle = state.viewStyle
    }

    /// Applies scene state that arrived after the window appeared, as the Mac restores it.
    func restore(_ state: State) {
        isRestoring = true
        defer { isRestoring = false }
        filters = Self.filters(from: state)
        storedCategoryID = state.activeCategoryID
        sortStrategy = state.sortStrategy
        sortReversed = state.sortReversed
        groupStrategy = Self.groupStrategy(from: state)
        viewStyle = state.viewStyle
    }

    private static func filters(from state: State) -> Set<LibraryStore.AnimeFilter> {
        Set(state.filterIDs.compactMap(LibraryStore.AnimeFilter.init(preferenceID:)))
    }

    /// Score grouping falls back to none while scoring is off.
    private static func groupStrategy(from state: State) -> LibraryStore.LibraryGroupStrategy {
        state.groupStrategy == .score && !isScoringEnabled ? .none : state.groupStrategy
    }

    var state: State {
        State(
            filterIDs: filters.map(\.id).sorted(),
            activeCategoryID: storedCategoryID,
            sortStrategy: sortStrategy,
            sortReversed: sortReversed,
            groupStrategy: groupStrategy,
            viewStyle: viewStyle
        )
    }

    /// The state a new window starts from: the default filters, All, and the stored sort,
    /// group, and view style preferences.
    static func seedState(from store: LibraryStore) -> State {
        State(
            filterIDs: store.defaultFilters.map(\.id).sorted(),
            activeCategoryID: nil,
            sortStrategy: store.sortStrategy,
            sortReversed: store.sortReversed,
            groupStrategy: store.groupStrategy,
            viewStyle: storedViewStylePreference
        )
    }

    // MARK: - Display list

    var displayItems: [LibraryEntryDisplayItem] { display.items }

    var displayIDs: [LibraryEntryIdentity] { display.ids }

    var entriesOnDisplay: [AnimeEntry] { display.items.map(\.entry) }

    /// The shown entry with this identity, if this window's scope and filters show it.
    func displayedEntry(for identity: LibraryEntryIdentity) -> AnimeEntry? {
        display.entriesByID[identity]
    }

    /// The filtered, sorted display list, recomputed only after something it read changes
    /// (docs-ai 023).
    ///
    /// Observation tracking covers every input the computation reads, including the entries'
    /// own properties, so unsaved edits such as favorite toggles invalidate it like saves do.
    /// The cache is cleared in the input's `willSet` and rebuilt on the next read, which runs in
    /// the mutating caller's transaction and keeps its animation.
    private var display: LibraryDisplayCache {
        _ = displayGeneration
        if let displayCache { return displayCache }
        displayComputeCount += 1
        let cache = withObservationTracking {
            LibraryDisplayCache(
                items: filterAndSort(store.library).map { entry in
                    // SwiftData can hand out new instances of child models such as episode
                    // progress between reads, so edits to them may never reach this tracking.
                    // Tracked edits also stamp the entry's own clock, which is observed reliably.
                    _ = entry.trackingUpdatedAt
                    return LibraryEntryDisplayItem(entry: entry)
                }
            )
        } onChange: { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.invalidateDisplay() }
            } else {
                Task { @MainActor in self?.invalidateDisplay() }
            }
        }
        if !isInvalidatingDisplay {
            displayCache = cache
        }
        return cache
    }

    private func invalidateDisplay() {
        isInvalidatingDisplay = true
        defer { isInvalidatingDisplay = false }
        displayCache = nil
        displayGeneration &+= 1
        LibraryBenchmarkSignposts.displayDidInvalidate()
    }

    func filterAndSort(_ entries: [AnimeEntry]) -> [AnimeEntry] {
        // The active category narrows the library before the status and type filters (AND).
        let scopedEntries: [AnimeEntry]
        if let activeCategoryID {
            scopedEntries = entries.filter { $0.categoryIDs.contains(activeCategoryID) }
        } else {
            scopedEntries = entries
        }
        return scopedEntries.filter(matchesBrowseFilters).sorted(by: compareEntriesForDisplay)
    }

    // MARK: - Scope

    var activeCategory: LibraryCategory? {
        guard let activeCategoryID else { return nil }
        return store.categories.first { $0.id == activeCategoryID }
    }

    /// Whether a jump can show the entry; the jump itself leaves a category that hides it.
    func canRevealEntry(_ identity: LibraryEntryIdentity) -> Bool {
        store.library.contains { $0.libraryIdentity == identity && matchesBrowseFilters($0) }
    }

    /// Clears the filters so a search jump can show the entry, opting into Dropped for this
    /// window when Hide Dropped Entries would still hide it; the preference stays unchanged.
    func resetFiltersToReveal(_ identity: LibraryEntryIdentity) {
        filters = []
        if !canRevealEntry(identity) {
            filters = [.dropped]
        }
    }

    /// Leaves the category when it hides the entry; a jump spans the whole library.
    func leaveCategoryToReveal(_ identity: LibraryEntryIdentity) {
        guard activeCategoryID != nil, displayedEntry(for: identity) == nil else { return }
        activeCategoryID = nil
    }

    /// Applies new default filters, as changing Default Filters in Settings does.
    func applyDefaultFilters() {
        filters = store.defaultFilters
    }

    /// Deletes an entry and moves the scroll position to its neighbor in this window's order.
    @discardableResult
    func deleteEntry(
        _ entry: AnimeEntry,
        updateScrolledID: (LibraryEntryIdentity?) -> Void
    ) -> Bool {
        let scrollTarget = deletionScrollTarget(for: entry)
        guard store.deleteEntry(entry) else { return false }
        switch scrollTarget {
        case .preserveCurrent:
            break
        case .clear:
            updateScrolledID(nil)
        case .entry(let targetID):
            updateScrolledID(targetID)
        }
        return true
    }

    // MARK: - Private

    private enum DeletionScrollTarget: Equatable {
        case preserveCurrent
        case clear
        case entry(LibraryEntryIdentity)
    }

    private func deletionScrollTarget(for entry: AnimeEntry) -> DeletionScrollTarget {
        let ids = displayIDs
        guard let index = ids.firstIndex(of: entry.libraryIdentity) else {
            return .preserveCurrent
        }
        if index > 0 {
            return .entry(ids[index - 1])
        }
        let nextIndex = index + 1
        guard nextIndex < ids.endIndex else {
            return .clear
        }
        return .entry(ids[nextIndex])
    }

    private func matchesBrowseFilters(_ entry: AnimeEntry) -> Bool {
        if store.hideDroppedByDefault && !filters.contains(.dropped) && entry.watchStatus == .dropped {
            return false
        }
        return filters.isEmpty || filters.contains { $0.evaluate(entry) }
    }

    private func compareEntriesForDisplay(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        let lhsGroupRank = groupStrategy.rank(for: lhs)
        let rhsGroupRank = groupStrategy.rank(for: rhs)

        if lhsGroupRank != rhsGroupRank {
            return lhsGroupRank < rhsGroupRank
        }

        return compareWithinCurrentGroup(lhs, rhs)
    }

    private func compareWithinCurrentGroup(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        let comparisons: [(AnimeEntry, AnimeEntry) -> Bool] = [
            sortStrategy.compare,
            { $0.dateSaved < $1.dateSaved },
            { $0.tmdbID < $1.tmdbID }
        ]

        // Reverse only applies to the ordering inside each active group.
        for comparison in comparisons {
            if comparison(lhs, rhs) {
                return !sortReversed
            }
            if comparison(rhs, lhs) {
                return sortReversed
            }
        }

        return false
    }

    private static var isScoringEnabled: Bool {
        UserDefaults.standard.bool(forKey: .libraryScoringEnabled, defaultValue: true)
    }

    private static var storedViewStylePreference: LibraryViewStyle {
        UserDefaults.standard.string(forKey: .libraryViewStyle)
            .flatMap(LibraryViewStyle.init(rawValue:)) ?? .gallery
    }

    private static func saveViewStylePreference(_ style: LibraryViewStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: .libraryViewStyle)
    }
}
