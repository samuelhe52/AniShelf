//
//  LibraryDisplayOrder.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/31.
//

import DataProvider
import Foundation

/// Every entry value any window's filters, category, grouping, or sort can use.
///
/// Reading the same values whatever the window's settings keeps one observation registration
/// valid across setting changes, and sorting compares these plain values instead of reading
/// SwiftData properties on every comparison (docs-ai 040).
struct LibraryDisplayOrderInputs: Equatable {
    let passingFilterIDs: Set<String>
    let isDropped: Bool
    let categoryIDs: [String]
    let groupRanks: [LibraryStore.LibraryGroupStrategy: Int]
    let name: String
    let dateSaved: Date
    let dateStarted: Date?
    let dateFinished: Date?
    let onAirDate: Date?
    let tmdbID: Int

    init(entry: AnimeEntry) {
        passingFilterIDs = Set(LibraryStore.AnimeFilter.allCases.lazy.filter { $0.evaluate(entry) }.map(\.id))
        isDropped = entry.watchStatus == .dropped
        categoryIDs = entry.categoryIDs
        groupRanks = Dictionary(
            uniqueKeysWithValues: LibraryStore.LibraryGroupStrategy.allCases.map { ($0, $0.rank(for: entry)) }
        )
        name = entry.name
        dateSaved = entry.dateSaved
        dateStarted = entry.dateStarted
        dateFinished = entry.dateFinished
        onAirDate = entry.onAirDate
        tmdbID = entry.tmdbID
    }
}

/// The window settings that decide which entries show and in which order.
struct LibraryDisplayOrderDefinition: Equatable {
    var filters: Set<LibraryStore.AnimeFilter>
    var activeCategoryID: LibraryCategory.ID?
    var hidesDropped: Bool
    var sortStrategy: LibraryStore.AnimeSortStrategy
    var sortReversed: Bool
    var groupStrategy: LibraryStore.LibraryGroupStrategy

    func key(for inputs: LibraryDisplayOrderInputs) -> LibraryDisplayOrderKey {
        LibraryDisplayOrderKey(
            isShown: isShown(inputs),
            groupRank: inputs.groupRanks[groupStrategy] ?? 0,
            primary: primaryValue(for: inputs),
            dateSaved: inputs.dateSaved,
            tmdbID: inputs.tmdbID
        )
    }

    /// Group ranks ascend; inside a group the sort value, then the saved date, then the TMDb ID
    /// decide, and only that ordering reverses.
    func precedes(_ lhs: LibraryDisplayOrderKey, _ rhs: LibraryDisplayOrderKey) -> Bool {
        if lhs.groupRank != rhs.groupRank {
            return lhs.groupRank < rhs.groupRank
        }
        var result = lhs.primary.compare(to: rhs.primary)
        if result == .orderedSame { result = Self.compare(lhs.dateSaved, rhs.dateSaved) }
        if result == .orderedSame { result = Self.compare(lhs.tmdbID, rhs.tmdbID) }
        guard result != .orderedSame else { return false }
        return (result == .orderedAscending) != sortReversed
    }

    fileprivate static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

    private func isShown(_ inputs: LibraryDisplayOrderInputs) -> Bool {
        // The active category narrows the library before the status and type filters (AND).
        if let activeCategoryID, !inputs.categoryIDs.contains(activeCategoryID) { return false }
        if hidesDropped && !filters.contains(.dropped) && inputs.isDropped { return false }
        return filters.isEmpty || filters.contains { inputs.passingFilterIDs.contains($0.id) }
    }

    private func primaryValue(for inputs: LibraryDisplayOrderInputs) -> LibraryDisplayOrderKey.Primary {
        switch sortStrategy {
        case .dateSaved: .date(inputs.dateSaved)
        case .dateStarted: .date(inputs.dateStarted ?? .distantFuture)
        case .dateFinished: .date(inputs.dateFinished ?? .distantFuture)
        case .dateOnAir: .date(inputs.onAirDate ?? .distantFuture)
        case .alphabetical: .name(inputs.name)
        }
    }
}

/// One entry's place in the display order under one definition.
struct LibraryDisplayOrderKey: Equatable {
    enum Primary: Equatable {
        case date(Date)
        case name(String)

        func compare(to other: Primary) -> ComparisonResult {
            switch (self, other) {
            case (.date(let lhs), .date(let rhs)):
                LibraryDisplayOrderDefinition.compare(lhs, rhs)
            case (.name(let lhs), .name(let rhs)):
                // Like the sort, names that compare equal fall through to the next key.
                lhs.localizedStandardCompare(rhs)
            default:
                .orderedSame
            }
        }
    }

    let isShown: Bool
    let groupRank: Int
    let primary: Primary
    let dateSaved: Date
    let tmdbID: Int
}
