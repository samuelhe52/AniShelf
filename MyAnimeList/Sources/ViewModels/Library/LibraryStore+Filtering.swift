//
//  LibraryStore+Filtering.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/7.
//

import DataProvider
import Foundation
import SwiftUI

extension LibraryStore {
    private enum EntryTypeBucket: Equatable {
        case movies
        case tvSeries

        init(entry: AnimeEntry) {
            switch entry.type {
            case .movie:
                self = .movies
            case .series, .season(_, _):
                self = .tvSeries
            }
        }

        var rank: Int {
            switch self {
            case .movies:
                return 1
            case .tvSeries:
                return 0
            }
        }
    }

    struct AnimeFilter: Sendable, CaseIterable, Equatable, Hashable {
        static let favorited = AnimeFilter(id: "Favorites", name: "Favorites") { $0.favorite }
        static let watched = AnimeFilter(id: "Watched", name: "Watched") {
            $0.watchStatus == .watched
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
        static let movies = AnimeFilter(id: "Movies", name: "Movies") {
            EntryTypeBucket(entry: $0) == .movies
        }
        static let tvSeries = AnimeFilter(id: "TV Series", name: "TV Series") {
            EntryTypeBucket(entry: $0) == .tvSeries
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
            [.favorited, .watched, .planToWatch, .watching, .dropped, .movies, .tvSeries]
        }

        static var typeCases: [LibraryStore.AnimeFilter] {
            [.tvSeries, .movies]
        }

        static var watchStatusCases: [LibraryStore.AnimeFilter] {
            [.dropped, .watching, .planToWatch, .watched]
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
        case dateSaved, dateStarted, dateFinished, dateOnAir, alphabetical

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
            case .alphabetical:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .dateFinished: "Date Finished"
            case .dateSaved: "Date Saved"
            case .dateStarted: "Date Started"
            case .dateOnAir: "Date On Air"
            case .alphabetical: "Name"
            }
        }
    }

    enum LibraryGroupStrategy: String,
        CaseIterable,
        CustomLocalizedStringResourceConvertible,
        Codable
    {
        case none, watchStatus, score, favorite, entryType

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
            case .entryType:
                return EntryTypeBucket(entry: entry).rank
            }
        }

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .none: "None"
            case .watchStatus: "Watch Status"
            case .score: "Score"
            case .favorite: "Favorite"
            case .entryType: "Entry Type"
            }
        }
    }
}
