import DataProvider
import Foundation
import SwiftUI

extension LibraryStore {
    func filterAndSort(_ entries: [AnimeEntry]) -> [AnimeEntry] {
        let sorted: [AnimeEntry]
        if !sortReversed {
            sorted =
                entries
                .sorted(by: sortStrategy.compare)
        } else {
            sorted =
                entries
                .sorted(by: sortStrategy.compare)
                .reversed()
        }
        let defaultDisplayEntries: [AnimeEntry]
        if hideDroppedByDefault && !filters.contains(.dropped) {
            defaultDisplayEntries = sorted.filter { $0.watchStatus != .dropped }
        } else {
            defaultDisplayEntries = sorted
        }
        guard filters.isEmpty else {
            return defaultDisplayEntries.filter { entry in
                filters.contains { filter in
                    filter.evaluate(entry)
                }
            }
        }
        return defaultDisplayEntries
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
}
