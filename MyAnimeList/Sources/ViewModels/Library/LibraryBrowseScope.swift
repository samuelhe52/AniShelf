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

    /// What this window shows and in which order; changing it scrolls back to the top
    /// (docs-ai 038). View style is not part of it: a style switch keeps the position.
    struct DisplayDefinition: Equatable {
        var filters: Set<LibraryStore.AnimeFilter>
        var activeCategoryID: LibraryCategory.ID?
        var sortStrategy: LibraryStore.AnimeSortStrategy
        var sortReversed: Bool
        var groupStrategy: LibraryStore.LibraryGroupStrategy
    }

    var displayDefinition: DisplayDefinition {
        DisplayDefinition(
            filters: filters,
            activeCategoryID: activeCategoryID,
            sortStrategy: sortStrategy,
            sortReversed: sortReversed,
            groupStrategy: groupStrategy
        )
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

    /// The filtered, sorted display list, rebuilt only where something it read changed
    /// (docs-ai 023 and 040).
    ///
    /// Observation tracking covers every input the computation reads, including the entries'
    /// own properties, so unsaved edits such as favorite toggles invalidate it like saves do.
    /// Each entry has its own registration: a change to one entry rebuilds only that entry's
    /// row and order inputs, and re-sorts only if those inputs changed. The assembled list is
    /// cleared in the input's `willSet` and rebuilt on the next read, which runs in the
    /// mutating caller's transaction and keeps its animation.
    private var display: LibraryDisplayCache {
        _ = displayGeneration
        if let displayCache { return displayCache }
        displayComputeCount += 1
        // A read during an invalidation runs in the input's `willSet` and sees the old values;
        // answer it without storing anything, as the next read rebuilds anyway.
        guard !isInvalidatingDisplay else {
            return LibraryDisplayCache(items: filterAndSort(store.library).map(LibraryEntryDisplayItem.init))
        }
        isComputingDisplay = true
        let cache = computeDisplay()
        isComputingDisplay = false
        displayCache = cache
        // Changes reported while computing apply now, so none is lost to the stored records.
        let deferred = deferredInvalidations
        deferredInvalidations = []
        for invalidation in deferred { invalidation(self) }
        return cache
    }

    private func computeDisplay() -> LibraryDisplayCache {
        let library = trackListInputs()
        var needsSort = order == nil
        var keptRecords: [ObjectIdentifier: EntryRecord] = [:]
        keptRecords.reserveCapacity(library.count)
        for entry in library {
            let id = ObjectIdentifier(entry)
            let record: EntryRecord
            if let cached = records[id], !cached.isStale {
                record = cached
            } else {
                record = track(entry)
            }
            if records[id]?.inputs != record.inputs { needsSort = true }
            keptRecords[id] = record
        }
        records = keptRecords

        if needsSort {
            let definition = orderDefinition
            order =
                library
                .compactMap { entry in
                    records[ObjectIdentifier(entry)].map { (entry, definition.key(for: $0.inputs)) }
                }
                .filter(\.1.isShown)
                .sorted { definition.precedes($0.1, $1.1) }
                .map(\.0)
        }
        return LibraryDisplayCache(items: (order ?? []).compactMap { records[ObjectIdentifier($0)]?.item })
    }

    // MARK: - Display records

    /// One entry's row and order inputs, observed by one registration.
    ///
    /// The registration reads the same values whatever this window's filters or sort, so a
    /// setting change reuses it: Observation offers no way to cancel a registration before
    /// it fires, and replacing registrations on every change would pile up observers on each
    /// entry. A record registers again only after its registration fired.
    private struct EntryRecord {
        let item: LibraryEntryDisplayItem
        let inputs: LibraryDisplayOrderInputs
        let token: UInt64
        var isStale = false
    }

    @ObservationIgnored private var records: [ObjectIdentifier: EntryRecord] = [:]
    /// The shown entries in display order; `nil` once they need sorting again.
    @ObservationIgnored private var order: [AnimeEntry]?
    @ObservationIgnored private var trackedLibrary: [AnimeEntry]?
    @ObservationIgnored private var listToken: UInt64?
    @ObservationIgnored private var trackingToken: UInt64 = 0
    /// How many row snapshots were built; tests use it to check that updates stay per entry.
    @ObservationIgnored private(set) var rowBuildCount = 0

    private var orderDefinition: LibraryDisplayOrderDefinition {
        LibraryDisplayOrderDefinition(
            filters: filters,
            activeCategoryID: activeCategoryID,
            hidesDropped: store.hideDroppedByDefault,
            sortStrategy: sortStrategy,
            sortReversed: sortReversed,
            groupStrategy: groupStrategy
        )
    }

    /// Reads the library and this window's settings; a change to them sorts again.
    private func trackListInputs() -> [AnimeEntry] {
        if let trackedLibrary { return trackedLibrary }
        let token = nextToken()
        listToken = token
        let library = withObservationTracking {
            _ = orderDefinition
            return store.library
        } onChange: { [weak self] in
            self?.onMain { scope in
                guard scope.listToken == token else { return }
                scope.listToken = nil
                scope.trackedLibrary = nil
                scope.order = nil
                scope.invalidateDisplay()
            }
        }
        trackedLibrary = library
        return library
    }

    private func track(_ entry: AnimeEntry) -> EntryRecord {
        let id = ObjectIdentifier(entry)
        let token = nextToken()
        rowBuildCount += 1
        let (item, inputs) = withObservationTracking {
            // SwiftData can hand out new instances of child models such as episode progress
            // between reads, so edits to them may never reach this tracking. Tracked edits also
            // stamp the entry's own clock, which is observed reliably.
            _ = entry.trackingUpdatedAt
            // Background writes and import replays change values without observation, and a
            // refetch can hand out new child-model instances that this registration does not
            // observe. Their explicit refresh signals fire every record's registration, which
            // also removes it, so each entry registers again on current instances (docs-ai 039).
            _ = store.libraryRevision
            _ = store.backgroundWriteRevision
            return (LibraryEntryDisplayItem(entry: entry), LibraryDisplayOrderInputs(entry: entry))
        } onChange: { [weak self] in
            self?.onMain { scope in
                guard scope.records[id]?.token == token else { return }
                scope.records[id]?.isStale = true
                scope.invalidateDisplay()
            }
        }
        return EntryRecord(item: item, inputs: inputs, token: token)
    }

    private func nextToken() -> UInt64 {
        trackingToken &+= 1
        return trackingToken
    }

    @ObservationIgnored private var isComputingDisplay = false
    @ObservationIgnored private var deferredInvalidations: [@MainActor (LibraryBrowseScope) -> Void] = []

    private nonisolated func onMain(_ body: @escaping @MainActor (LibraryBrowseScope) -> Void) {
        let run: @MainActor (LibraryBrowseScope) -> Void = { scope in
            if scope.isComputingDisplay {
                scope.deferredInvalidations.append(body)
            } else {
                body(scope)
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { run(self) }
        } else {
            Task { @MainActor in run(self) }
        }
    }

    private func invalidateDisplay() {
        // Many records can report one change together, as a revision bump does; the first
        // report already told readers to rebuild.
        guard displayCache != nil else { return }
        isInvalidatingDisplay = true
        defer { isInvalidatingDisplay = false }
        displayCache = nil
        displayGeneration &+= 1
        LibraryBenchmarkSignposts.displayDidInvalidate()
    }

    func filterAndSort(_ entries: [AnimeEntry]) -> [AnimeEntry] {
        let definition = orderDefinition
        return entries.map { ($0, definition.key(for: LibraryDisplayOrderInputs(entry: $0))) }
            .filter(\.1.isShown)
            .sorted { definition.precedes($0.1, $1.1) }
            .map(\.0)
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

    // MARK: - Private

    private func matchesBrowseFilters(_ entry: AnimeEntry) -> Bool {
        if store.hideDroppedByDefault && !filters.contains(.dropped) && entry.watchStatus == .dropped {
            return false
        }
        return filters.isEmpty || filters.contains { $0.evaluate(entry) }
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
