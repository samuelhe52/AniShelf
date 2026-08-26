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

@Observable @MainActor
class TMDbSearchService {
    private struct SearchRequest: Equatable {
        let query: String
        let language: Language
    }

    @ObservationIgnored let client: TMDbSearchClient
    private(set) var status: Status = .loaded
    private(set) var movieResults: [EntryMetadata] = []
    private(set) var seriesResults: [EntryMetadata] = []
    // Batch state is mutated from TMDbSearchService+Batch.swift.
    var batchStatus: BatchStatus = .idle
    var batchResults: [TMDbBatchPromptResult] = []
    var batchSearchGeneration = 0

    private var regularResultsToSubmit: OrderedSet<SearchResult> = []
    private var batchResultsToSubmit: OrderedSet<SearchResult> = []
    private var regularSeriesSelectionStates: [Int: TMDbSeriesSelectionState] = [:]
    private var batchSeriesSelectionStates: [Int: TMDbSeriesSelectionState] = [:]

    @ObservationIgnored private var latestRequest: SearchRequest?
    @ObservationIgnored var latestBatchRequestID: UUID?
    @ObservationIgnored var batchPromptCacheKey: [String] = []
    @ObservationIgnored var checkDuplicate: (LibraryEntryIdentity) -> Bool
    @ObservationIgnored var processResults: (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void

    init(
        client: TMDbSearchClient = .live(),
        checkDuplicate: @escaping (LibraryEntryIdentity) -> Bool = { _ in false },
        processResults: @escaping (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void = { _, _ in }
    ) {
        self.client = client
        self.checkDuplicate = checkDuplicate
        self.processResults = processResults
    }

    func isDuplicate(_ result: SearchResult) -> Bool {
        checkDuplicate(result.libraryIdentity)
    }

    /// Submit the final results.
    func submit() { processResults(OrderedSet(regularResultsToSubmit.reversed()), .regular) }
    /// Submit the final batch results.
    func submitBatch() { processResults(OrderedSet(batchResultsToSubmit.reversed()), .batch) }
    /// The count of all regular-search results pending submission.
    var registeredCount: Int { regularResultsToSubmit.count }
    var batchRegisteredCount: Int { batchResultsToSubmit.count }
    var batchRegisteredSeriesCount: Int { batchRegisteredCount(for: .series) }
    var batchRegisteredSeasonCount: Int { batchSelectionSeasonCount() }
    var batchRegisteredMovieCount: Int { batchRegisteredCount(for: .movie) }

    func isRegistered(info: EntryMetadata) -> Bool {
        containsSelection(.init(tmdbID: info.tmdbID, type: info.type), in: .regular)
    }

    func isBatchSelected(info: EntryMetadata) -> Bool {
        containsSelection(.init(tmdbID: info.tmdbID, type: info.type), in: .batch)
    }

    func seriesSelectionState(
        for series: EntryMetadata,
        context: TMDbSelectionContext
    ) -> TMDbSeriesSelectionState {
        seriesSelectionState(forSeriesID: series.tmdbID, context: context)
    }

    /// Appends a result to the regular-search submission queue.
    func register(_ result: SearchResult) {
        setSelection(true, result: result, context: .regular)
    }

    /// Creates a result from an `EntryMetadata` for the regular-search submission queue.
    func register(info: EntryMetadata) {
        setSelection(true, info: info, context: .regular)
    }

    /// Removes a result from the regular-search submission queue if it is present.
    func unregister(_ result: SearchResult) {
        setSelection(false, result: result, context: .regular)
    }

    /// Removes a result corresponding to the provided `EntryMetadata` from the regular-search submission queue if it is present.
    func unregister(info: EntryMetadata) {
        setSelection(false, info: info, context: .regular)
    }

    /// Registers a result that belongs to the active batch session.
    func registerBatchSelection(info: EntryMetadata) {
        setSelection(true, info: info, context: .batch)
    }

    /// Removes a batch-owned result from the submission queue if it is present.
    func unregisterBatchSelection(info: EntryMetadata) {
        setSelection(false, info: info, context: .batch)
    }

    func setSelection(_ isSelected: Bool, for info: EntryMetadata, context: TMDbSelectionContext) {
        setSelection(isSelected, info: info, context: context)
    }

    func setSeasonSelection(
        _ isSelected: Bool,
        for season: EntryMetadata,
        context: TMDbSelectionContext
    ) {
        setSelection(isSelected, info: season, context: context)
    }

    func setSeriesSelectionMode(
        _ mode: TMDbSeriesSelectionMode,
        for series: EntryMetadata,
        language: Language,
        context: TMDbSelectionContext
    ) async {
        var state = seriesSelectionState(forSeriesID: series.tmdbID, context: context)
        state.selectedMode = mode

        switch mode {
        case .series:
            clearSeasonSelections(forSeriesID: series.tmdbID, context: context, state: &state)
        case .season:
            setSelection(false, info: series, context: context)
        }

        setSeriesSelectionState(state, forSeriesID: series.tmdbID, context: context)

        guard mode == .season else { return }
        await fetchSeasonsIfNeeded(for: series, language: language, context: context)
    }

    /// Removes all regular-search selections.
    func clearAll() {
        clearSelections(in: .regular)
        logger.info("Cleared all regular registered results.")
    }

    private func batchRegisteredCount(for type: AnimeType) -> Int {
        batchResultsToSubmit.reduce(into: 0) { count, result in
            if result.type == type {
                count += 1
            }
        }
    }

    private func batchSelectionSeasonCount() -> Int {
        batchResultsToSubmit.reduce(into: 0) { count, result in
            if case .season = result.type {
                count += 1
            }
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

    @discardableResult
    private func insertResult(_ result: SearchResult, context: TMDbSelectionContext) -> Bool {
        let inserted: Bool
        switch context {
        case .regular:
            let (didInsert, _) = regularResultsToSubmit.insert(result, at: 0)
            inserted = didInsert
        case .batch:
            let (didInsert, _) = batchResultsToSubmit.insert(result, at: 0)
            inserted = didInsert
        }
        if inserted {
            logger.info(
                "Registered \(self.selectionContextLabel(context)) result: \(result.tmdbID) of type \(result.type)."
            )
        } else {
            logger.info(
                "\(self.selectionContextLabel(context)) result already registered: \(result.tmdbID) of type \(result.type)."
            )
        }
        return inserted
    }

    @discardableResult
    private func removeResult(_ result: SearchResult, context: TMDbSelectionContext) -> Bool {
        let removed: Bool
        switch context {
        case .regular:
            removed = regularResultsToSubmit.remove(result) != nil
        case .batch:
            removed = batchResultsToSubmit.remove(result) != nil
        }
        if removed {
            logger.info(
                "Unregistered \(self.selectionContextLabel(context)) result: \(result.tmdbID) of type \(result.type)."
            )
        } else {
            logger.info(
                "\(self.selectionContextLabel(context)) result not found for unregistration: \(result.tmdbID) of type \(result.type)."
            )
        }
        return removed
    }

    private func containsSelection(_ result: SearchResult, in context: TMDbSelectionContext) -> Bool {
        switch context {
        case .regular:
            regularResultsToSubmit.contains(result)
        case .batch:
            batchResultsToSubmit.contains(result)
        }
    }

    private func setSelection(
        _ isSelected: Bool,
        info: EntryMetadata,
        context: TMDbSelectionContext
    ) {
        setSelection(
            isSelected,
            result: .init(tmdbID: info.tmdbID, type: info.type),
            context: context
        )
    }

    private func setSelection(
        _ isSelected: Bool,
        result: SearchResult,
        context: TMDbSelectionContext
    ) {
        if isSelected {
            _ = insertResult(result, context: context)
        } else {
            _ = removeResult(result, context: context)
        }
        syncSeriesSelectionState(for: result, context: context, isSelected: isSelected)
    }

    private func syncSeriesSelectionState(
        for result: SearchResult,
        context: TMDbSelectionContext,
        isSelected: Bool
    ) {
        switch result.type {
        case .series:
            var state = seriesSelectionState(forSeriesID: result.tmdbID, context: context)
            state.selectedMode = .series
            setSeriesSelectionState(state, forSeriesID: result.tmdbID, context: context)
        case .season(_, let parentSeriesID):
            var state = seriesSelectionState(forSeriesID: parentSeriesID, context: context)
            state.selectedMode = .season
            if isSelected {
                state.selectedSeasonIDs.insert(result.tmdbID)
            } else {
                state.selectedSeasonIDs.remove(result.tmdbID)
            }
            setSeriesSelectionState(state, forSeriesID: parentSeriesID, context: context)
        case .movie:
            break
        }
    }

    func seriesSelectionState(
        forSeriesID seriesID: Int,
        context: TMDbSelectionContext
    ) -> TMDbSeriesSelectionState {
        switch context {
        case .regular:
            regularSeriesSelectionStates[seriesID] ?? .init()
        case .batch:
            batchSeriesSelectionStates[seriesID] ?? .init()
        }
    }

    func setSeriesSelectionState(
        _ state: TMDbSeriesSelectionState,
        forSeriesID seriesID: Int,
        context: TMDbSelectionContext
    ) {
        switch context {
        case .regular:
            regularSeriesSelectionStates[seriesID] = state
        case .batch:
            batchSeriesSelectionStates[seriesID] = state
        }
    }

    private func clearSeasonSelections(
        forSeriesID seriesID: Int,
        context: TMDbSelectionContext,
        state: inout TMDbSeriesSelectionState
    ) {
        for season in state.seasons where state.selectedSeasonIDs.contains(season.tmdbID) {
            _ = removeResult(.init(tmdbID: season.tmdbID, type: season.type), context: context)
        }
        state.selectedSeasonIDs.removeAll()
    }

    func clearSelections(in context: TMDbSelectionContext) {
        switch context {
        case .regular:
            regularResultsToSubmit.removeAll()
            regularSeriesSelectionStates.removeAll()
        case .batch:
            batchResultsToSubmit.removeAll()
            batchSeriesSelectionStates.removeAll()
        }
    }

    private func selectionContextLabel(_ context: TMDbSelectionContext) -> String {
        switch context {
        case .regular:
            "regular"
        case .batch:
            "batch"
        }
    }

    private func fetchSeasonsIfNeeded(
        for seriesInfo: EntryMetadata,
        language: Language,
        context: TMDbSelectionContext
    ) async {
        var state = seriesSelectionState(forSeriesID: seriesInfo.tmdbID, context: context)
        guard state.seasonFetchStatus == .notStarted else { return }

        state.seasonFetchStatus = .fetching
        setSeriesSelectionState(state, forSeriesID: seriesInfo.tmdbID, context: context)

        let generation = context == .batch ? batchSearchGeneration : nil
        let seasons = await fetchSeasons(for: seriesInfo, language: language)

        if let generation, generation != batchSearchGeneration {
            return
        }

        state = seriesSelectionState(forSeriesID: seriesInfo.tmdbID, context: context)
        state.seasons = seasons
        state.seasonFetchStatus = .fetched
        state.selectedSeasonIDs.formIntersection(Set(seasons.map(\.tmdbID)))
        setSeriesSelectionState(state, forSeriesID: seriesInfo.tmdbID, context: context)
    }

    private func fetchSeasons(for seriesInfo: EntryMetadata, language: Language) async -> [EntryMetadata] {
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
