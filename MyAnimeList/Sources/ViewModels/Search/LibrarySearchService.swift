//
//  LibrarySearchService.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/5.
//


import DataProvider
import Foundation
import SwiftData
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "LibrarySearchService")

@Observable @MainActor
class LibrarySearchService {
    private let dataProvider = DataProvider.default
    private var entries: [AnimeEntry] = []
    var jumpToEntryInLibrary: (Int) -> Void

    private(set) var results: [AnimeEntry] = []
    private(set) var status: Status = .loaded

    init(
        jumpToEntryInLibrary: @escaping (Int) -> Void = { _ in }
    ) {
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
        loadModels()
        if query.isEmpty {
            results = []
        } else {
            let lowercasedQuery = query.lowercased()
            withAnimation {
                results = searchInLibrary(query: lowercasedQuery)
            }
        }
        status = .loaded
    }

    private func loadModels() {
        do {
            entries = try dataProvider.getAllModels(ofType: AnimeEntry.self)
        } catch {
            logger.error("Error loading AnimeEntry models: \(error)")
            status = .error(error)
        }
    }

    private func searchInLibrary(query: String) -> [AnimeEntry] {
        let lowercasedQuery = query.lowercased()

        var results: [AnimeEntry] = []
        var processedIDs = Set<Int>()

        func addToResults(evaluate: (AnimeEntry) -> Bool) {
            for entry in entries where !processedIDs.contains(entry.tmdbID) {
                guard entry.onDisplay else { continue }
                if evaluate(entry) {
                    results.append(entry)
                    processedIDs.insert(entry.tmdbID)
                }
            }
        }

        // Priority 1: Name matches (displayName)
        addToResults { $0.displayName.lowercased().contains(lowercasedQuery) }

        // Priority 2: Name translations
        addToResults {
            $0.nameTranslations.contains(where: { $0.value.lowercased().contains(lowercasedQuery) })
        }

        // Priority 3: Parent series matches
        addToResults { entry in
            guard let parentSeries = entry.parentSeriesEntry else { return false }
            return parentSeries.overview?.lowercased().contains(lowercasedQuery) ?? false
                || parentSeries.displayName.lowercased().contains(lowercasedQuery)
                || parentSeries.nameTranslations.contains(where: {
                    $0.value.lowercased().contains(lowercasedQuery)
                })
                || parentSeries.overviewTranslations.contains(where: {
                    $0.value.lowercased().contains(lowercasedQuery)
                })
        }

        // Priority 4: Overview matches
        addToResults { $0.overview?.lowercased().contains(lowercasedQuery) ?? false }

        // Priority 5: Overview translations
        addToResults {
            $0.overviewTranslations.contains(where: {
                $0.value.lowercased().contains(lowercasedQuery)
            })
        }

        // Priority 6: Notes matches
        addToResults { $0.notes.lowercased().contains(lowercasedQuery) }

        // Priority 7: Date matches
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        addToResults { entry in
            if let onAirDate = entry.onAirDate {
                let dateString = dateFormatter.string(from: onAirDate).lowercased()
                if dateString.contains(lowercasedQuery) {
                    return true
                }
            }
            return false
        }

        return results
    }
}
