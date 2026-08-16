//
//  TVMazeResolver.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/10.
//

import DataProvider
import Foundation

enum TVMazeAutomaticResolution: Equatable, Sendable {
    case resolved(TVMazeShow)
    case requiresUserAssistance
    case ineligible
}

/// Resolves AniShelf entries to hydrated TVMaze shows.
///
/// Identifier discovery and show retrieval remain internal steps. Automatic resolution never
/// performs title search, while user-initiated search stays read-only until a candidate is
/// explicitly confirmed.
struct TVMazeResolver: Sendable {
    // MARK: - Dependencies

    /// Returns a previously confirmed TVMaze show ID for a TMDb series ID.
    private let loadMappedShowID: @Sendable (Int) async throws -> Int?

    /// Records a confirmed TVMaze show ID for a TMDb series ID.
    private let saveMappedShowID: @Sendable (Int, Int) async throws -> Void

    /// Finds the TVMaze show ID associated with a TVDB ID.
    private let lookupTVDBShowID: @Sendable (Int) async throws -> Int?

    /// Finds the TVMaze show ID associated with an IMDb ID.
    private let lookupIMDbShowID: @Sendable (String) async throws -> Int?

    /// Returns TVMaze's ranked title-search results.
    private let searchShows: @Sendable (String) async throws -> [TVMazeShow]

    /// Retrieves the hydrated TVMaze show, including its embedded next episode.
    private let fetchShow: @Sendable (Int) async throws -> TVMazeShow?

    // MARK: - Initialization

    init(
        tvMazeClient: TVMazeClient = TVMazeClient(),
        mappingStore: TVMazeConfirmedMappingStore = .shared
    ) {
        self.init(
            loadMappedShowID: { tmdbSeriesID in
                await mappingStore.showID(forTMDbSeriesID: tmdbSeriesID)
            },
            saveMappedShowID: { tmdbSeriesID, tvMazeShowID in
                await mappingStore.confirm(
                    showID: tvMazeShowID,
                    forTMDbSeriesID: tmdbSeriesID
                )
            },
            lookupTVDBShowID: { tvdbID in
                try await tvMazeClient.lookupShowID(tvdbID: tvdbID)
            },
            lookupIMDbShowID: { imdbID in
                try await tvMazeClient.lookupShowID(imdbID: imdbID)
            },
            searchShows: { title in
                try await tvMazeClient.searchShows(named: title)
            },
            fetchShow: { tvMazeID in
                try await tvMazeClient.show(id: tvMazeID)
            }
        )
    }

    init(
        loadMappedShowID: @escaping @Sendable (Int) async throws -> Int?,
        saveMappedShowID: @escaping @Sendable (Int, Int) async throws -> Void,
        lookupTVDBShowID: @escaping @Sendable (Int) async throws -> Int?,
        lookupIMDbShowID: @escaping @Sendable (String) async throws -> Int?,
        searchShows: @escaping @Sendable (String) async throws -> [TVMazeShow],
        fetchShow: @escaping @Sendable (Int) async throws -> TVMazeShow?
    ) {
        self.loadMappedShowID = loadMappedShowID
        self.saveMappedShowID = saveMappedShowID
        self.lookupTVDBShowID = lookupTVDBShowID
        self.lookupIMDbShowID = lookupIMDbShowID
        self.searchShows = searchShows
        self.fetchShow = fetchShow
    }

    // MARK: - Automatic Resolution

    /// Resolves an eligible entry without performing title search.
    func resolve(
        entryType: AnimeType,
        tmdbID: Int,
        externalIDs: TMDbSeriesExternalIDs
    ) async throws -> TVMazeAutomaticResolution {
        guard let tmdbSeriesID = seriesTMDbID(entryType: entryType, tmdbID: tmdbID) else {
            return .ineligible
        }

        if let mappedShowID = try await loadMappedShowID(tmdbSeriesID),
            let show = try await fetchShow(mappedShowID)
        {
            return .resolved(show)
        }

        if let tvdbID = externalIDs.tvdbID,
            let showID = try await lookupTVDBShowID(tvdbID),
            let show = try await fetchShow(showID)
        {
            try await saveMappedShowID(tmdbSeriesID, show.id)
            return .resolved(show)
        }

        if let imdbID = externalIDs.imdbID,
            let showID = try await lookupIMDbShowID(imdbID),
            let show = try await fetchShow(showID)
        {
            try await saveMappedShowID(tmdbSeriesID, show.id)
            return .resolved(show)
        }

        return .requiresUserAssistance
    }

    // MARK: - User-Initiated Title Fallback

    /// Searches by title and retrieves the full candidate as one resolver operation.
    ///
    /// Calling this method does not persist a TMDb-to-TVMaze mapping. The caller must wait for
    /// explicit user confirmation before recording one.
    func resolveTitleFallback(named title: String) async throws -> TVMazeShow? {
        guard let candidate = try await searchTitleCandidates(named: title).first else {
            return nil
        }
        return try await hydrateTitleCandidate(id: candidate.id)
    }

    /// Returns every ranked title-search result without changing the saved mapping.
    func searchTitleCandidates(named title: String) async throws -> [TVMazeShow] {
        try await searchShows(title)
    }

    /// Retrieves full schedule and next-episode details for a selected search result.
    func hydrateTitleCandidate(id: Int) async throws -> TVMazeShow? {
        try await fetchShow(id)
    }

    /// Records a title-search candidate only after the user explicitly confirms it.
    ///
    /// Seasons are stored against their parent series. Movies remain ineligible and return
    /// `false` without writing a mapping.
    @discardableResult
    func confirmTitleFallbackCandidate(
        _ candidate: TVMazeShow,
        entryType: AnimeType,
        tmdbID: Int
    ) async throws -> Bool {
        guard let tmdbSeriesID = seriesTMDbID(entryType: entryType, tmdbID: tmdbID) else {
            return false
        }

        try await saveMappedShowID(tmdbSeriesID, candidate.id)
        return true
    }

    // MARK: - Entry Identity

    private func seriesTMDbID(entryType: AnimeType, tmdbID: Int) -> Int? {
        switch entryType {
        case .series:
            tmdbID
        case .season(_, let parentSeriesID):
            parentSeriesID
        case .movie:
            nil
        }
    }
}
