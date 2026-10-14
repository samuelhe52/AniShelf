//
//  LibrarySearchService.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/5.
//

import DataProvider
import Foundation
import SwiftUI

@Observable @MainActor
class LibrarySearchService {
    @ObservationIgnored var entriesProvider: @MainActor () -> [AnimeEntry] = { [] }
    var jumpToEntryInLibrary: (LibraryEntryIdentity) -> Void

    private(set) var results: [AnimeEntry] = []
    private(set) var status: Status = .loaded

    init(
        entriesProvider: @escaping @MainActor () -> [AnimeEntry] = { [] },
        jumpToEntryInLibrary: @escaping (LibraryEntryIdentity) -> Void = { _ in }
    ) {
        self.entriesProvider = entriesProvider
        self.jumpToEntryInLibrary = jumpToEntryInLibrary
    }

    enum Status: Equatable {
        case loading
        case loaded
        case error(Error)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.loaded, .loaded):
                return true
            case (.error(let e1), .error(let e2)):
                return (e1 as NSError).domain == (e2 as NSError).domain
                    && (e1 as NSError).code == (e2 as NSError).code
            default:
                return false
            }
        }
    }

    func updateResults(query: String) {
        status = .loading
        if query.isEmpty {
            results = []
            status = .loaded
        } else {
            withAnimation {
                results = LibrarySearchMatcher.search(query, in: entriesProvider())
            }
            status = .loaded
        }
    }
}

/// Ranks library entries for a text query, tier by tier.
///
/// The search sheet uses every tier. App Intents skip notes and dates so a Shortcuts
/// search never matches on personal text.
enum LibrarySearchMatcher {
    enum Tier: CaseIterable {
        case name
        case nameTranslations
        case parentSeries
        case overview
        case overviewTranslations
        case notes
        case onAirDate
    }

    static let metadataTiers: [Tier] = [
        .name, .nameTranslations, .parentSeries, .overview, .overviewTranslations
    ]

    /// Returns visible entries matching `query`, ordered by the first tier each one matches.
    static func search(
        _ query: String,
        in entries: [AnimeEntry],
        tiers: [Tier] = Tier.allCases
    ) -> [AnimeEntry] {
        let lowercasedQuery = query.lowercased()

        var results: [AnimeEntry] = []
        var processedIdentities = Set<LibraryEntryIdentity>()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        for tier in tiers {
            for entry in entries where !processedIdentities.contains(entry.libraryIdentity) {
                guard entry.onDisplay else { continue }
                if matches(entry, tier: tier, lowercasedQuery: lowercasedQuery, dateFormatter: dateFormatter) {
                    results.append(entry)
                    processedIdentities.insert(entry.libraryIdentity)
                }
            }
        }

        return results
    }

    /// Matches entries by the same rules as the search page, without its ranking.
    ///
    /// The Mac toolbar's Find filters the visible library with it.
    static func matcher(for query: String, tiers: [Tier] = Tier.allCases) -> (AnimeEntry) -> Bool {
        let lowercasedQuery = query.lowercased()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return { entry in
            tiers.contains {
                matches(entry, tier: $0, lowercasedQuery: lowercasedQuery, dateFormatter: dateFormatter)
            }
        }
    }

    private static func matches(
        _ entry: AnimeEntry,
        tier: Tier,
        lowercasedQuery: String,
        dateFormatter: DateFormatter
    ) -> Bool {
        switch tier {
        case .name:
            entry.displayName.lowercased().contains(lowercasedQuery)
        case .nameTranslations:
            entry.nameTranslations.contains(where: { $0.value.lowercased().contains(lowercasedQuery) })
        case .parentSeries:
            entry.parentSeriesEntry.map { parentSeries in
                parentSeries.overview?.lowercased().contains(lowercasedQuery) ?? false
                    || parentSeries.displayName.lowercased().contains(lowercasedQuery)
                    || parentSeries.nameTranslations.contains(where: {
                        $0.value.lowercased().contains(lowercasedQuery)
                    })
                    || parentSeries.overviewTranslations.contains(where: {
                        $0.value.lowercased().contains(lowercasedQuery)
                    })
            } ?? false
        case .overview:
            entry.overview?.lowercased().contains(lowercasedQuery) ?? false
        case .overviewTranslations:
            entry.overviewTranslations.contains(where: {
                $0.value.lowercased().contains(lowercasedQuery)
            })
        case .notes:
            entry.notes.lowercased().contains(lowercasedQuery)
        case .onAirDate:
            entry.onAirDate.map {
                dateFormatter.string(from: $0).lowercased().contains(lowercasedQuery)
            } ?? false
        }
    }
}
