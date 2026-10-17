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
                results = searchInLibrary(
                    query: query.lowercased(),
                    entries: entriesProvider()
                )
            }
            status = .loaded
        }
    }

    private func searchInLibrary(query: String, entries: [AnimeEntry]) -> [AnimeEntry] {
        let lowercasedQuery = query.lowercased()

        var results: [AnimeEntry] = []
        var processedIdentities = Set<LibraryEntryIdentity>()

        // Earlier predicates rank higher: name, translations, parent series, overview,
        // overview translations, notes, then air date.
        for predicate in Self.matchPredicates(lowercasedQuery: lowercasedQuery) {
            for entry in entries where !processedIdentities.contains(entry.libraryIdentity) {
                guard entry.onDisplay else { continue }
                if predicate(entry) {
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
    static func matcher(for query: String) -> (AnimeEntry) -> Bool {
        let predicates = matchPredicates(lowercasedQuery: query.lowercased())
        return { entry in predicates.contains { $0(entry) } }
    }

    private static func matchPredicates(lowercasedQuery: String) -> [(AnimeEntry) -> Bool] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return [
            // Priority 1: Name matches (displayName)
            { $0.displayName.lowercased().contains(lowercasedQuery) },
            // Priority 2: Name translations
            { $0.nameTranslations.contains(where: { $0.value.lowercased().contains(lowercasedQuery) }) },
            // Priority 3: Parent series matches
            { entry in
                guard let parentSeries = entry.parentSeriesEntry else { return false }
                return parentSeries.overview?.lowercased().contains(lowercasedQuery) ?? false
                    || parentSeries.displayName.lowercased().contains(lowercasedQuery)
                    || parentSeries.nameTranslations.contains(where: {
                        $0.value.lowercased().contains(lowercasedQuery)
                    })
                    || parentSeries.overviewTranslations.contains(where: {
                        $0.value.lowercased().contains(lowercasedQuery)
                    })
            },
            // Priority 4: Overview matches
            { $0.overview?.lowercased().contains(lowercasedQuery) ?? false },
            // Priority 5: Overview translations
            {
                $0.overviewTranslations.contains(where: {
                    $0.value.lowercased().contains(lowercasedQuery)
                })
            },
            // Priority 6: Notes matches
            { $0.notes.lowercased().contains(lowercasedQuery) },
            // Priority 7: Date matches
            { entry in
                guard let onAirDate = entry.onAirDate else { return false }
                return dateFormatter.string(from: onAirDate).lowercased().contains(lowercasedQuery)
            }
        ]
    }
}
