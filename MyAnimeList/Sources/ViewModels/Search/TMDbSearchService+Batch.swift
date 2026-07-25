//
//  TMDbSearchService+Batch.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import DataProvider
import Foundation
import SwiftUI
import os

fileprivate let batchLogger = Logger(subsystem: .bundleIdentifier, category: "TMDbSearchService")

extension TMDbSearchService {
    private struct BatchSeasonPreselection: Equatable, Sendable {
        let series: EntryMetadata
        let seasons: [EntryMetadata]
        let selectedSeason: EntryMetadata
    }

    private struct BatchPromptResolution: Equatable, Sendable {
        let result: TMDbBatchPromptResult
        let seasonPreselection: BatchSeasonPreselection?
    }

    nonisolated private static let batchPromptChunkSize = 8

    func performBatchSearch(input: String, language: Language) async {
        let prompts = Self.parsedBatchPrompts(from: input)

        guard !prompts.isEmpty else {
            clearBatchSession()
            return
        }

        if canReuseBatchResults(for: prompts) {
            return
        }

        let requestID = UUID()
        latestBatchRequestID = requestID
        clearSelections(in: .batch)
        withAnimation {
            batchResults = []
            batchStatus = .loading
            batchSearchGeneration += 1
        }

        do {
            let promptResults = try await fetchBatchResults(prompts: prompts, language: language)
            guard latestBatchRequestID == requestID else { return }
            withAnimation {
                applyBatchResults(promptResults, prompts: prompts)
                batchStatus = .loaded
                batchSearchGeneration += 1
            }
        } catch {
            guard latestBatchRequestID == requestID else { return }
            batchLogger.error("Error fetching batch search results: \(error)")
            withAnimation {
                batchResults = []
                batchStatus = .error(error)
                batchSearchGeneration += 1
            }
        }
    }

    func clearBatchSession() {
        latestBatchRequestID = UUID()
        clearSelections(in: .batch)
        withAnimation {
            batchResults = []
            batchPromptCacheKey = []
            batchStatus = .idle
            batchSearchGeneration += 1
        }
    }

    func canReuseBatchResults(for input: String) -> Bool {
        let prompts = Self.parsedBatchPrompts(from: input)
        return canReuseBatchResults(for: prompts)
    }

    nonisolated static func batchPrompts(from input: String) -> [String] {
        input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func parsedBatchPrompts(from input: String) -> [TMDbBatchPrompt] {
        batchPrompts(from: input).map(TMDbBatchPrompt.init(displayText:))
    }

    nonisolated static func chunkedBatchPrompts(
        _ prompts: [String],
        chunkSize: Int = batchPromptChunkSize
    ) -> [[String]] {
        let normalizedChunkSize = max(1, chunkSize)
        return stride(from: 0, to: prompts.count, by: normalizedChunkSize).map { start in
            let end = min(start + normalizedChunkSize, prompts.count)
            return Array(prompts[start..<end])
        }
    }

    nonisolated static func chunkedBatchPrompts(
        _ prompts: [TMDbBatchPrompt],
        chunkSize: Int = batchPromptChunkSize
    ) -> [[TMDbBatchPrompt]] {
        let normalizedChunkSize = max(1, chunkSize)
        return stride(from: 0, to: prompts.count, by: normalizedChunkSize).map { start in
            let end = min(start + normalizedChunkSize, prompts.count)
            return Array(prompts[start..<end])
        }
    }

    private func fetchBatchResults(prompts: [TMDbBatchPrompt], language: Language) async throws
        -> [BatchPromptResolution]
    {
        let chunks = Self.chunkedBatchPrompts(prompts)
        var orderedResults = [BatchPromptResolution?](repeating: nil, count: prompts.count)

        for (chunkIndex, chunk) in chunks.enumerated() {
            let baseIndex = chunkIndex * Self.batchPromptChunkSize
            let chunkResults = try await withThrowingTaskGroup(
                of: (Int, BatchPromptResolution).self
            ) { group in
                for (offset, prompt) in chunk.enumerated() {
                    let index = baseIndex + offset
                    group.addTask { [client] in
                        (
                            index,
                            try await Self.resolveBatchPrompt(
                                prompt,
                                id: index,
                                language: language,
                                client: client
                            )
                        )
                    }
                }

                var results: [(Int, BatchPromptResolution)] = []
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

    private nonisolated static func resolveBatchPrompt(
        _ prompt: TMDbBatchPrompt,
        id: Int,
        language: Language,
        client: TMDbSearchClient
    ) async throws -> BatchPromptResolution {
        switch prompt {
        case .title(let displayText):
            async let seriesResults = client.searchTVSeries(displayText, language)
            async let movieResults = client.searchMovies(displayText, language)
            let resolvedSeriesResults = try await seriesResults
            let resolvedMovieResults = try await movieResults
            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: resolvedSeriesResults.first,
                    movie: resolvedMovieResults.first
                ),
                seasonPreselection: nil
            )

        case .movieID(let displayText, let tmdbID):
            let movie = try await client.fetchMovieByID(tmdbID, language)
            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: nil,
                    movie: movie
                ),
                seasonPreselection: nil
            )

        case .seriesID(let displayText, let tmdbID):
            let series = try await client.fetchTVSeriesByID(tmdbID, language)
            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: series,
                    movie: nil
                ),
                seasonPreselection: nil
            )

        case .season(let displayText, let seriesTMDbID, let seasonNumber):
            guard let series = try await client.fetchTVSeriesByID(seriesTMDbID, language) else {
                return BatchPromptResolution(
                    result: TMDbBatchPromptResult(
                        id: id,
                        prompt: displayText,
                        series: nil,
                        movie: nil
                    ),
                    seasonPreselection: nil
                )
            }

            let seasons = try await client.fetchSeasons(series, language)
            guard let selectedSeason = seasons.first(where: { $0.type.seasonNumber == seasonNumber })
            else {
                return BatchPromptResolution(
                    result: TMDbBatchPromptResult(
                        id: id,
                        prompt: displayText,
                        series: nil,
                        movie: nil
                    ),
                    seasonPreselection: nil
                )
            }

            return BatchPromptResolution(
                result: TMDbBatchPromptResult(
                    id: id,
                    prompt: displayText,
                    series: series,
                    movie: nil
                ),
                seasonPreselection: BatchSeasonPreselection(
                    series: series,
                    seasons: seasons,
                    selectedSeason: selectedSeason
                )
            )
        }
    }

    private func applyBatchResults(_ resolutions: [BatchPromptResolution], prompts: [TMDbBatchPrompt]) {
        batchResults = resolutions.map(\.result)
        batchPromptCacheKey = prompts.map(\.displayText)

        let structuredSeasonResultIDs = Set(
            resolutions.compactMap { $0.seasonPreselection?.series.tmdbID }
        )
        for resolution in resolutions where resolution.seasonPreselection == nil {
            for info in resolution.result.allInfos {
                if case .series = info.type, structuredSeasonResultIDs.contains(info.tmdbID) {
                    continue
                }
                guard !checkDuplicate(info.tmdbID) else { continue }
                registerBatchSelection(info: info)
            }
        }

        for preselection in resolutions.compactMap(\.seasonPreselection) {
            var state = seriesSelectionState(forSeriesID: preselection.series.tmdbID, context: .batch)
            state.selectedMode = .season
            state.seasons = preselection.seasons
            state.seasonFetchStatus = .fetched
            setSeriesSelectionState(state, forSeriesID: preselection.series.tmdbID, context: .batch)
            unregisterBatchSelection(info: preselection.series)

            guard !checkDuplicate(preselection.selectedSeason.tmdbID) else { continue }
            registerBatchSelection(info: preselection.selectedSeason)
        }
    }

    private func canReuseBatchResults(for prompts: [TMDbBatchPrompt]) -> Bool {
        batchStatus == .loaded && batchPromptCacheKey == prompts.map(\.displayText)
    }

    enum BatchStatus {
        case idle
        case loading
        case loaded
        case error(Error)
    }
}
