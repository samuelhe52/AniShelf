import DataProvider
import Foundation
import SwiftUI

extension LibraryStore {
    func filterAndSort(_ entries: [AnimeEntry]) -> [AnimeEntry] {
        let defaultDisplayEntries: [AnimeEntry]
        if hideDroppedByDefault && !filters.contains(.dropped) {
            defaultDisplayEntries = entries.filter { $0.watchStatus != .dropped }
        } else {
            defaultDisplayEntries = entries
        }
        let filteredEntries: [AnimeEntry]
        guard filters.isEmpty else {
            filteredEntries = defaultDisplayEntries.filter { entry in
                filters.contains { filter in
                    filter.evaluate(entry)
                }
            }
            return filteredEntries.sorted(by: compareEntriesForDisplay)
        }
        filteredEntries = defaultDisplayEntries
        return filteredEntries.sorted(by: compareEntriesForDisplay)
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
            compareByDateSaved,
            compareByTMDbID
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

    private func compareByDateSaved(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        lhs.dateSaved < rhs.dateSaved
    }

    private func compareByTMDbID(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        lhs.tmdbID < rhs.tmdbID
    }

    struct AnimeFilter: Sendable, CaseIterable, Equatable, Hashable {
        static let favorited = AnimeFilter(id: "Favorites", name: "Favorites") { $0.favorite }
        static let watched = AnimeFilter(id: "Watched", name: "Watched") {
            $0.watchStatus == WatchedStatus.watched
        }
        static let planToWatch = AnimeFilter(id: "Plan to Watch", name: "Planned") {
            $0.watchStatus == .planToWatch
        }
        static let watching = AnimeFilter(id: "Watching", name: "Watching") {
            $0.watchStatus == .watching
        }
        static let dropped = AnimeFilter(id: "Dropped", name: "Dropped") {
            $0.watchStatus == .dropped
        }

        private init(
            id: String, name: LocalizedStringResource,
            evaluate: @escaping @Sendable (AnimeEntry) -> Bool
        ) {
            self.id = id
            self.name = name
            self.evaluate = evaluate
        }

        let id: String
        let name: LocalizedStringResource
        let evaluate: @Sendable (AnimeEntry) -> Bool

        init?(preferenceID: String) {
            guard let filter = Self.allCases.first(where: { $0.id == preferenceID }) else {
                return nil
            }
            self = filter
        }

        static var allCases: [LibraryStore.AnimeFilter] {
            [.favorited, .watched, .planToWatch, .watching, .dropped]
        }

        static func == (lhs: LibraryStore.AnimeFilter, rhs: LibraryStore.AnimeFilter) -> Bool {
            lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum AnimeSortStrategy: String,
        CaseIterable,
        CustomLocalizedStringResourceConvertible,
        Codable
    {
        case dateSaved, dateStarted, dateFinished, dateOnAir

        func compare(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
            switch self {
            case .dateSaved:
                return lhs.dateSaved < rhs.dateSaved
            case .dateStarted:
                return lhs.dateStarted ?? .distantFuture < rhs.dateStarted ?? .distantFuture
            case .dateFinished:
                return lhs.dateFinished ?? .distantFuture < rhs.dateFinished ?? .distantFuture
            case .dateOnAir:
                return lhs.onAirDate ?? .distantFuture < rhs.onAirDate ?? .distantFuture
            }
        }

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .dateFinished: "Date Finished"
            case .dateSaved: "Date Saved"
            case .dateStarted: "Date Started"
            case .dateOnAir: "Date On Air"
            }
        }
    }

    enum LibraryGroupStrategy: String,
        CaseIterable,
        CustomLocalizedStringResourceConvertible,
        Codable
    {
        case none, watchStatus, score, favorite

        func rank(for entry: AnimeEntry) -> Int {
            switch self {
            case .none:
                return 0
            case .watchStatus:
                switch entry.watchStatus {
                case .watching:
                    return 0
                case .planToWatch:
                    return 1
                case .watched:
                    return 2
                case .dropped:
                    return 3
                }
            case .score:
                switch entry.score {
                case 5:
                    return 0
                case 4:
                    return 1
                case 3:
                    return 2
                case 2:
                    return 3
                case 1:
                    return 4
                default:
                    return 5
                }
            case .favorite:
                return entry.favorite ? 0 : 1
            }
        }

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .none: "None"
            case .watchStatus: "Watch Status"
            case .score: "Score"
            case .favorite: "Favorite"
            }
        }
    }
}
