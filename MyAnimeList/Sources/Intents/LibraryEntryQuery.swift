//
//  LibraryEntryQuery.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents
import DataProvider
import Foundation

/// Resolves, searches, and filters visible library entries for Shortcuts.
///
/// The `EntityPropertyQuery` conformance gives Shortcuts a native "Find Library Entries"
/// action. All work happens in `AppIntentLibraryContext` so tests can drive it directly.
struct LibraryEntryQuery: EntityStringQuery, EntityPropertyQuery {
    @Dependency private var context: AppIntentLibraryContext

    // Built once and never mutated; the App Intents builders are not marked Sendable.
    nonisolated(unsafe) static let properties = QueryProperties {
        Property(\LibraryEntryEntity.$status) {
            EqualToComparator { LibraryEntryPredicate.status($0) }
            NotEqualToComparator { LibraryEntryPredicate.statusNot($0) }
        }
        Property(\LibraryEntryEntity.$isFavorite) {
            EqualToComparator { LibraryEntryPredicate.favorite($0) }
        }
        Property(\LibraryEntryEntity.$score) {
            GreaterThanOrEqualToComparator { LibraryEntryPredicate.scoreAtLeast($0) }
        }
        Property(\LibraryEntryEntity.$name) {
            ContainsComparator { LibraryEntryPredicate.nameContains($0) }
        }
    }

    nonisolated(unsafe) static let sortingOptions = SortingOptions {
        SortableBy(\LibraryEntryEntity.$name)
        SortableBy(\LibraryEntryEntity.$dateSaved)
    }

    static var findIntentDescription: IntentDescription? {
        IntentDescription("Finds entries in your AniShelf library by status, favorite, score, or name.")
    }

    init() {}

    @MainActor
    func entities(for identifiers: [LibraryEntryEntity.ID]) async throws -> [LibraryEntryEntity] {
        try context.entities(for: identifiers)
    }

    @MainActor
    func entities(matching string: String) async throws -> [LibraryEntryEntity] {
        try context.entities(matching: string)
    }

    @MainActor
    func suggestedEntities() async throws -> [LibraryEntryEntity] {
        try context.suggestedEntities()
    }

    func entities(
        matching comparators: [LibraryEntryPredicate],
        mode: ComparatorMode,
        sortedBy: [Sort<LibraryEntryEntity>],
        limit: Int?
    ) async throws -> [LibraryEntryEntity] {
        // `EntityQuerySort` is not Sendable, so convert it before hopping to the main actor.
        try await entities(
            matching: comparators,
            requiringAll: mode == .and,
            sortedBy: sortedBy.compactMap(LibraryEntrySortDescriptor.init),
            limit: limit
        )
    }

    @MainActor
    private func entities(
        matching predicates: [LibraryEntryPredicate],
        requiringAll: Bool,
        sortedBy sortDescriptors: [LibraryEntrySortDescriptor],
        limit: Int?
    ) throws -> [LibraryEntryEntity] {
        try context.entities(
            matching: predicates,
            requiringAll: requiringAll,
            sortedBy: sortDescriptors,
            limit: limit
        )
    }
}

enum LibraryEntryPredicate: Equatable, Sendable {
    case status(WatchStatusAppEnum)
    case statusNot(WatchStatusAppEnum)
    case favorite(Bool)
    case scoreAtLeast(Int)
    case nameContains(String)

    @MainActor
    func matches(_ entry: AnimeEntry) -> Bool {
        switch self {
        case .status(let status):
            return entry.watchStatus == status.watchStatus
        case .statusNot(let status):
            return entry.watchStatus != status.watchStatus
        case .favorite(let isFavorite):
            return entry.favorite == isFavorite
        case .scoreAtLeast(let score):
            guard let entryScore = entry.score else { return false }
            return entryScore >= score
        case .nameContains(let text):
            let names = [entry.displayName, entry.name] + entry.nameTranslations.values
            return names.contains { $0.localizedStandardContains(text) }
        }
    }
}

struct LibraryEntrySortDescriptor: Equatable, Sendable {
    enum Key: Equatable, Sendable {
        case name
        case dateSaved
    }

    var key: Key
    var ascending: Bool

    init(key: Key, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    init?(_ sort: EntityQuerySort<LibraryEntryEntity>) {
        if sort.by == \LibraryEntryEntity.$name {
            key = .name
        } else if sort.by == \LibraryEntryEntity.$dateSaved {
            key = .dateSaved
        } else {
            return nil
        }
        ascending = sort.order == .ascending
    }
}

extension AppIntentLibraryContext {
    /// How many entries the Shortcuts picker suggests before the user searches.
    static let suggestedEntityLimit = 50

    func entities(for identifiers: [LibraryEntryEntity.ID]) throws -> [LibraryEntryEntity] {
        try requireUsableLibrary()
        let entriesByID = Dictionary(
            store.library.map { ($0.libraryIdentity.rawID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return identifiers.compactMap { entriesByID[$0].map(LibraryEntryEntity.init) }
    }

    /// Ranks entries with the library search tiers, without notes.
    func entities(matching string: String) throws -> [LibraryEntryEntity] {
        try requireUsableLibrary()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try suggestedEntities() }
        return LibrarySearchMatcher.search(
            query,
            in: entriesNewestFirst(),
            tiers: LibrarySearchMatcher.metadataTiers
        )
        .map(LibraryEntryEntity.init)
    }

    /// Watching entries by most recent tracking change, then the most recently saved.
    func suggestedEntities() throws -> [LibraryEntryEntity] {
        try requireUsableLibrary()
        let newestFirst = entriesNewestFirst()
        let watching = newestFirst.filter { $0.watchStatus == .watching }
            .sorted { ($0.trackingUpdatedAt ?? .distantPast) > ($1.trackingUpdatedAt ?? .distantPast) }
        let others = newestFirst.filter { $0.watchStatus != .watching }
        return (watching + others)
            .prefix(Self.suggestedEntityLimit)
            .map(LibraryEntryEntity.init)
    }

    func entities(
        matching predicates: [LibraryEntryPredicate],
        requiringAll: Bool,
        sortedBy sortDescriptors: [LibraryEntrySortDescriptor],
        limit: Int?
    ) throws -> [LibraryEntryEntity] {
        try requireUsableLibrary()
        var entries = entriesNewestFirst().filter { entry in
            guard !predicates.isEmpty else { return true }
            return requiringAll
                ? predicates.allSatisfy { $0.matches(entry) }
                : predicates.contains { $0.matches(entry) }
        }
        if !sortDescriptors.isEmpty {
            entries.sort { lhs, rhs in
                for descriptor in sortDescriptors {
                    let order: ComparisonResult =
                        switch descriptor.key {
                        case .name: lhs.displayName.localizedStandardCompare(rhs.displayName)
                        case .dateSaved: lhs.dateSaved.compare(rhs.dateSaved)
                        }
                    guard order != .orderedSame else { continue }
                    return descriptor.ascending ? order == .orderedAscending : order == .orderedDescending
                }
                return false
            }
        }
        if let limit {
            entries = Array(entries.prefix(max(0, limit)))
        }
        return entries.map(LibraryEntryEntity.init)
    }

    /// `store.library` has no meaningful order, so queries start from a stable one.
    private func entriesNewestFirst() -> [AnimeEntry] {
        store.library.sorted { lhs, rhs in
            if lhs.dateSaved != rhs.dateSaved { return lhs.dateSaved > rhs.dateSaved }
            return lhs.libraryIdentity.rawID < rhs.libraryIdentity.rawID
        }
    }
}
