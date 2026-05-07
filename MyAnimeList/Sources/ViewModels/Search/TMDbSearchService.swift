//
//  TMDbSearchService.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/5.
//

import Collections
import DataProvider
import Foundation
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "TMDbSearchService")

struct SearchResult: Hashable {
    var tmdbID: Int
    var type: AnimeType
}

@Observable @MainActor
class TMDbSearchService {
    private struct SearchRequest: Equatable {
        let query: String
        let language: Language
    }

    let fetcher: InfoFetcher = .init()
    private(set) var status: Status = .loaded
    private(set) var movieResults: [BasicInfo] = []
    private(set) var seriesResults: [BasicInfo] = []

    private var latestRequest: SearchRequest?
    private var resultsToSubmit: OrderedSet<SearchResult> = []
    var processResults: (OrderedSet<SearchResult>) -> Void

    init(
        processResults: @escaping (OrderedSet<SearchResult>) -> Void = { _ in }
    ) {
        self.processResults = processResults
    }

    /// Submit the final results.
    func submit() { processResults(OrderedSet(resultsToSubmit.reversed())) }
    /// The count of all results pending submission.
    var registeredCount: Int { resultsToSubmit.count }
    /// Appends a result to the submission queue.
    func register(_ result: SearchResult) {
        let (registered, _) = resultsToSubmit.insert(result, at: 0)
        if registered {
            logger.info("Registered result: \(result.tmdbID) of type \(result.type).")
        } else {
            logger.info("Result already registered: \(result.tmdbID) of type \(result.type).")
        }
    }
    /// Creates a result from a `BasicInfo` to the submission queue.
    func register(info: BasicInfo) {
        let (registered, _) = resultsToSubmit.insert(.init(tmdbID: info.tmdbID, type: info.type), at: 0)
        if registered {
            logger.info("Registered result: \(info.tmdbID) of type \(info.type).")
        } else {
            logger.info("Result already registered: \(info.tmdbID) of type \(info.type).")
        }
    }
    /// Removes a result from the submission queue if it is present.
    func unregister(_ result: SearchResult) {
        let unregistered = resultsToSubmit.remove(result) != nil
        if unregistered {
            logger.info("Unregistered result: \(result.tmdbID) of type \(result.type).")
        } else {
            logger.info("Result not found for unregistration: \(result.tmdbID) of type \(result.type).")
        }
    }
    /// Removes a result corresponding to the provided `BasicInfo` from the submission queue if it is present.
    func unregister(info: BasicInfo) {
        let unregistered = resultsToSubmit.remove(.init(tmdbID: info.tmdbID, type: info.type)) != nil
        if unregistered {
            logger.info("Unregistered result: \(info.tmdbID) of type \(info.type).")
        } else {
            logger.info("Result not found for unregistration: \(info.tmdbID) of type \(info.type).")
        }
    }
    /// Removes all series/movie results.
    func clearAll() {
        resultsToSubmit.removeAll()
        logger.info("Cleared all registered results.")
    }

    private func fetchPosterURLs(
        from items: [(tmdbID: Int, path: URL?)]
    ) async throws -> [(tmdbID: Int, url: URL?)] {
        try await withThrowingTaskGroup(of: (tmdbID: Int, url: URL?).self) { group in
            for item in items {
                group.addTask {
                    let url = try await self.fetcher
                        .tmdbClient
                        .imagesConfiguration
                        .posterURL(for: item.path, idealWidth: 200)
                    return (tmdbID: item.tmdbID, url: url)
                }
            }

            var results: [(tmdbID: Int, url: URL?)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    func updateResults(query: String, language: Language) {
        let request = SearchRequest(query: query, language: language)
        latestRequest = request

        guard !query.isEmpty else {
            withAnimation {
                movieResults = []
                seriesResults = []
            }
            status = .loaded
            return
        }
        Task {
            status = .loading
            do {
                let movies = try await fetcher.searchMovies(name: query, language: language)
                let tvSeries = try await fetcher.searchTVSeries(
                    name: query, language: language)
                let moviesPosterURLs = try await fetchPosterURLs(
                    from: movies.map { (tmdbID: $0.id, path: $0.posterPath) })
                let seriesPosterURLs = try await fetchPosterURLs(
                    from: tvSeries.map { (tmdbID: $0.id, path: $0.posterPath) })
                let searchMovieResults = movies.map { movie in
                    BasicInfo(
                        name: movie.title,
                        nameTranslations: [:],
                        overview: movie.overview,
                        overviewTranslations: [:],
                        posterURL: moviesPosterURLs.filter { $0.tmdbID == movie.id }.first?.url,
                        tmdbID: movie.id,
                        onAirDate: movie.releaseDate,
                        type: .movie)
                }
                let searchTVSeriesResults = tvSeries.map { series in
                    BasicInfo(
                        name: series.name,
                        nameTranslations: [:],
                        overview: series.overview,
                        overviewTranslations: [:],
                        posterURL: seriesPosterURLs.filter { $0.tmdbID == series.id }.first?.url,
                        tmdbID: series.id,
                        onAirDate: series.firstAirDate,
                        type: .series)
                }

                if request == latestRequest {
                    withAnimation {
                        movieResults = searchMovieResults
                        seriesResults = searchTVSeriesResults
                    }
                }
                status = .loaded
            } catch {
                logger.error("Error fetching search results: \(error)")
                status = .error(error)
            }
        }
    }


    func fetchSeasons(for seriesInfo: BasicInfo, language: Language) async -> [BasicInfo] {
        do {
            let fetcher = self.fetcher
            let series = try await fetcher.tvSeries(seriesInfo.tmdbID, language: language)
            guard let seasons = series.seasons else { return [] }
            let infos = try await withThrowingTaskGroup(of: BasicInfo.self) { group in
                var results: [BasicInfo] = []
                for season in seasons {
                    group.addTask {
                        let posterURL = try await fetcher.tmdbClient.imagesConfiguration
                            .posterURL(for: season.posterPath, idealWidth: 200)
                        return BasicInfo(
                            name: season.name,
                            nameTranslations: [:],
                            overview: season.overview,
                            overviewTranslations: [:],
                            posterURL: posterURL,
                            tmdbID: season.id,
                            onAirDate: season.airDate,
                            type: .season(seasonNumber: season.seasonNumber, parentSeriesID: seriesInfo.tmdbID))
                    }
                }
                for try await result in group {
                    results.append(result)
                }
                return results.sorted(by: {
                    if case .season(let seasonNumber1, _) = $0.type,
                        case .season(let seasonNumber2, _) = $1.type
                    {
                        return seasonNumber1 < seasonNumber2
                    }
                    return false
                })
            }
            return infos
        } catch {
            logger.error("Error fetching seasons for series \(seriesInfo.tmdbID): \(error)")
            status = .error(error)
            ToastCenter.global.completionState = .failed("Network Error!")
            return []
        }
    }

    enum Status {
        case loading
        case loaded
        case error(Error)
    }
}

extension TMDbSearchService.Status: Equatable {
    static func == (lhs: TMDbSearchService.Status, rhs: TMDbSearchService.Status) -> Bool {
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
