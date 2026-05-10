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
import TMDb
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "TMDbSearchService")

struct SearchResult: Hashable, Sendable {
    var tmdbID: Int
    var type: AnimeType
}

struct TMDbBatchPromptResult: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let prompt: String
    let series: BasicInfo?
    let movie: BasicInfo?
    var hasNoResults: Bool { series == nil && movie == nil }
    var allInfos: [BasicInfo] { [series, movie].compactMap { $0 } }
}

struct TMDbSearchClient: Sendable {
    let searchMovies: @Sendable (String, Language) async throws -> [BasicInfo]
    let searchTVSeries: @Sendable (String, Language) async throws -> [BasicInfo]
    let fetchSeasons: @Sendable (BasicInfo, Language) async throws -> [BasicInfo]

    init(
        searchMovies: @escaping @Sendable (String, Language) async throws -> [BasicInfo],
        searchTVSeries: @escaping @Sendable (String, Language) async throws -> [BasicInfo],
        fetchSeasons: @escaping @Sendable (BasicInfo, Language) async throws -> [BasicInfo]
    ) {
        self.searchMovies = searchMovies
        self.searchTVSeries = searchTVSeries
        self.fetchSeasons = fetchSeasons
    }

    static func live(fetcher: InfoFetcher = .init()) -> Self {
        Self(
            searchMovies: { query, language in
                let movies = try await fetcher.searchMovies(name: query, language: language)
                let posterURLs = try await fetchPosterURLMap(
                    fetcher: fetcher,
                    from: movies.map { (tmdbID: $0.id, path: $0.posterPath) }
                )
                return movies.map { movie in
                    BasicInfo(
                        name: movie.title,
                        nameTranslations: [:],
                        overview: movie.overview,
                        overviewTranslations: [:],
                        posterURL: posterURLs[movie.id] ?? nil,
                        tmdbID: movie.id,
                        onAirDate: movie.releaseDate,
                        type: .movie
                    )
                }
            },
            searchTVSeries: { query, language in
                let tvSeries = try await fetcher.searchTVSeries(name: query, language: language)
                let posterURLs = try await fetchPosterURLMap(
                    fetcher: fetcher,
                    from: tvSeries.map { (tmdbID: $0.id, path: $0.posterPath) }
                )
                return tvSeries.map { series in
                    BasicInfo(
                        name: series.name,
                        nameTranslations: [:],
                        overview: series.overview,
                        overviewTranslations: [:],
                        posterURL: posterURLs[series.id] ?? nil,
                        tmdbID: series.id,
                        onAirDate: series.firstAirDate,
                        type: .series
                    )
                }
            },
            fetchSeasons: { seriesInfo, language in
                let series = try await fetcher.tvSeries(seriesInfo.tmdbID, language: language)
                guard let seasons = series.seasons else { return [] }

                let infos = try await withThrowingTaskGroup(of: BasicInfo.self) { group in
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
                                type: .season(
                                    seasonNumber: season.seasonNumber,
                                    parentSeriesID: seriesInfo.tmdbID
                                )
                            )
                        }
                    }

                    var results: [BasicInfo] = []
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
            }
        )
    }
}

fileprivate func fetchPosterURLMap(
    fetcher: InfoFetcher,
    from items: [(tmdbID: Int, path: URL?)]
) async throws -> [Int: URL?] {
    let posterURLs = try await withThrowingTaskGroup(of: (tmdbID: Int, url: URL?).self) { group in
        for item in items {
            group.addTask {
                let url =
                    try await fetcher
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

    return Dictionary(uniqueKeysWithValues: posterURLs.map { ($0.tmdbID, $0.url) })
}

@Observable @MainActor
class TMDbSearchService {
    private struct SearchRequest: Equatable {
        let query: String
        let language: Language
    }

    private static let batchPromptChunkSize = 8

    @ObservationIgnored private let client: TMDbSearchClient
    private(set) var status: Status = .loaded
    private(set) var movieResults: [BasicInfo] = []
    private(set) var seriesResults: [BasicInfo] = []
    private(set) var batchStatus: BatchStatus = .idle
    private(set) var batchResults: [TMDbBatchPromptResult] = []
    private(set) var batchSearchGeneration = 0

    @ObservationIgnored private var latestRequest: SearchRequest?
    @ObservationIgnored private var latestBatchRequestID: UUID?
    @ObservationIgnored private var currentBatchDisplayedResults = OrderedSet<SearchResult>()
    @ObservationIgnored private var batchOwnedResults = OrderedSet<SearchResult>()
    @ObservationIgnored private var batchPromptCacheKey: [String] = []
    private var resultsToSubmit: OrderedSet<SearchResult> = []
    @ObservationIgnored var checkDuplicate: (Int) -> Bool
    @ObservationIgnored var processResults: (OrderedSet<SearchResult>) -> Void

    init(
        client: TMDbSearchClient = .live(),
        checkDuplicate: @escaping (Int) -> Bool = { _ in false },
        processResults: @escaping (OrderedSet<SearchResult>) -> Void = { _ in }
    ) {
        self.client = client
        self.checkDuplicate = checkDuplicate
        self.processResults = processResults
    }

    /// Submit the final results.
    func submit() { processResults(OrderedSet(resultsToSubmit.reversed())) }
    /// The count of all results pending submission.
    var registeredCount: Int { resultsToSubmit.count }
    var batchRegisteredCount: Int {
        currentBatchDisplayedResults.reduce(into: 0) { count, result in
            if resultsToSubmit.contains(result) {
                count += 1
            }
        }
    }
    func isRegistered(info: BasicInfo) -> Bool {
        resultsToSubmit.contains(.init(tmdbID: info.tmdbID, type: info.type))
    }
    /// Appends a result to the submission queue.
    func register(_ result: SearchResult) {
        _ = insertResult(result)
    }
    /// Creates a result from a `BasicInfo` to the submission queue.
    func register(info: BasicInfo) {
        _ = insertResult(.init(tmdbID: info.tmdbID, type: info.type))
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
    /// Registers a result that belongs to the active batch session.
    func registerBatchSelection(info: BasicInfo) {
        let result = SearchResult(tmdbID: info.tmdbID, type: info.type)
        if insertResult(result) {
            batchOwnedResults.insert(result, at: 0)
        }
    }
    /// Removes a batch-owned result from the submission queue if it is present.
    func unregisterBatchSelection(info: BasicInfo) {
        let result = SearchResult(tmdbID: info.tmdbID, type: info.type)
        batchOwnedResults.remove(result)
        unregister(result)
    }
    /// Removes all series/movie results.
    func clearAll() {
        resultsToSubmit.removeAll()
        logger.info("Cleared all registered results.")
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
                async let searchMovieResults = client.searchMovies(query, language)
                async let searchTVSeriesResults = client.searchTVSeries(query, language)
                let resolvedMovieResults = try await searchMovieResults
                let resolvedSeriesResults = try await searchTVSeriesResults

                if request == latestRequest {
                    withAnimation {
                        movieResults = resolvedMovieResults
                        seriesResults = resolvedSeriesResults
                    }
                    status = .loaded
                }
            } catch {
                logger.error("Error fetching search results: \(error)")
                guard request == latestRequest else { return }
                status = .error(error)
            }
        }
    }

    func performBatchSearch(input: String, language: Language) async {
        let prompts = Self.batchPrompts(from: input)

        guard !prompts.isEmpty else {
            clearBatchSession()
            return
        }

        if canReuseBatchResults(for: prompts) {
            return
        }

        let requestID = UUID()
        latestBatchRequestID = requestID
        clearBatchOwnedSelections()
        batchResults = []
        batchStatus = .loading
        batchSearchGeneration += 1

        do {
            let promptResults = try await fetchBatchResults(prompts: prompts, language: language)
            guard latestBatchRequestID == requestID else { return }
            applyBatchResults(promptResults, prompts: prompts)
            batchStatus = .loaded
            batchSearchGeneration += 1
        } catch {
            guard latestBatchRequestID == requestID else { return }
            logger.error("Error fetching batch search results: \(error)")
            batchResults = []
            batchStatus = .error(error)
            batchSearchGeneration += 1
        }
    }

    func clearBatchSession() {
        latestBatchRequestID = UUID()
        clearBatchOwnedSelections()
        batchResults = []
        batchPromptCacheKey = []
        batchStatus = .idle
        batchSearchGeneration += 1
    }

    func canReuseBatchResults(for input: String) -> Bool {
        let prompts = Self.batchPrompts(from: input)
        return canReuseBatchResults(for: prompts)
    }

    nonisolated static func batchPrompts(from input: String) -> [String] {
        input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func chunkedBatchPrompts(
        _ prompts: [String],
        chunkSize: Int = 8
    )
        -> [[String]]
    {
        let normalizedChunkSize = max(1, chunkSize)
        return stride(from: 0, to: prompts.count, by: normalizedChunkSize).map { start in
            let end = min(start + normalizedChunkSize, prompts.count)
            return Array(prompts[start..<end])
        }
    }

    private func fetchBatchResults(prompts: [String], language: Language) async throws
        -> [TMDbBatchPromptResult]
    {
        let chunks = Self.chunkedBatchPrompts(prompts)
        var orderedResults = [TMDbBatchPromptResult?](repeating: nil, count: prompts.count)

        for (chunkIndex, chunk) in chunks.enumerated() {
            let baseIndex = chunkIndex * Self.batchPromptChunkSize
            let chunkResults = try await withThrowingTaskGroup(
                of: (Int, TMDbBatchPromptResult).self
            ) { group in
                for (offset, prompt) in chunk.enumerated() {
                    let index = baseIndex + offset
                    group.addTask { [client] in
                        async let seriesResults = client.searchTVSeries(prompt, language)
                        async let movieResults = client.searchMovies(prompt, language)
                        let resolvedSeriesResults = try await seriesResults
                        let resolvedMovieResults = try await movieResults
                        let topSeries = resolvedSeriesResults.first
                        let topMovie = resolvedMovieResults.first
                        return (
                            index,
                            TMDbBatchPromptResult(
                                id: index,
                                prompt: prompt,
                                series: topSeries,
                                movie: topMovie
                            )
                        )
                    }
                }

                var results: [(Int, TMDbBatchPromptResult)] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }

            for (index, result) in chunkResults {
                orderedResults[index] = result
            }
        }

        return orderedResults.compactMap { $0 }
    }

    private func applyBatchResults(_ promptResults: [TMDbBatchPromptResult], prompts: [String]) {
        batchResults = promptResults
        currentBatchDisplayedResults = OrderedSet(
            promptResults
                .flatMap(\.allInfos)
                .map { SearchResult(tmdbID: $0.tmdbID, type: $0.type) }
        )
        batchPromptCacheKey = prompts

        for info in promptResults.flatMap(\.allInfos) where !checkDuplicate(info.tmdbID) {
            registerBatchSelection(info: info)
        }
    }

    private func canReuseBatchResults(for prompts: [String]) -> Bool {
        batchStatus == .loaded && batchPromptCacheKey == prompts
    }

    private func clearBatchOwnedSelections() {
        for result in batchOwnedResults {
            unregister(result)
        }
        batchOwnedResults.removeAll()
        currentBatchDisplayedResults.removeAll()
    }

    @discardableResult
    private func insertResult(_ result: SearchResult) -> Bool {
        let (registered, _) = resultsToSubmit.insert(result, at: 0)
        if registered {
            logger.info("Registered result: \(result.tmdbID) of type \(result.type).")
        } else {
            logger.info("Result already registered: \(result.tmdbID) of type \(result.type).")
        }
        return registered
    }

    func fetchSeasons(for seriesInfo: BasicInfo, language: Language) async -> [BasicInfo] {
        do {
            return try await client.fetchSeasons(seriesInfo, language)
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

    enum BatchStatus {
        case idle
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

extension TMDbSearchService.BatchStatus: Equatable {
    static func == (lhs: TMDbSearchService.BatchStatus, rhs: TMDbSearchService.BatchStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded):
            return true
        case (.error(let e1), .error(let e2)):
            return (e1 as NSError).domain == (e2 as NSError).domain
                && (e1 as NSError).code == (e2 as NSError).code
        default:
            return false
        }
    }
}
