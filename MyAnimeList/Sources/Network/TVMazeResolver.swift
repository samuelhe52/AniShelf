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
/// performs title search, while ``resolveTitleFallback(named:)`` always searches and retrieves
/// the full show before returning a candidate.
struct TVMazeResolver: Sendable {
    // MARK: - Dependencies

    /// Returns a previously confirmed TVMaze show ID for a TMDb series ID.
    private let loadMappedShowID: @Sendable (Int) async throws -> Int?

    /// Retrieves the TVDB and IMDb identifiers attached to a TMDb series.
    private let fetchExternalIDs: @Sendable (Int) async throws -> TMDbSeriesExternalIDs

    /// Finds the TVMaze show ID associated with a TVDB ID.
    private let lookupTVDBShowID: @Sendable (Int) async throws -> Int?

    /// Finds the TVMaze show ID associated with an IMDb ID.
    private let lookupIMDbShowID: @Sendable (String) async throws -> Int?

    /// Returns the top title-search result's TVMaze show ID.
    private let searchShowID: @Sendable (String) async throws -> Int?

    /// Retrieves the hydrated TVMaze show, including its embedded next episode.
    private let fetchShow: @Sendable (Int) async throws -> TVMazeShow?

    // MARK: - Initialization

    init(
        infoFetcher: InfoFetcher = InfoFetcher(),
        tvMazeClient: TVMazeClient = TVMazeClient(),
        loadMappedShowID: @escaping @Sendable (Int) async throws -> Int? = { _ in nil }
    ) {
        self.init(
            loadMappedShowID: loadMappedShowID,
            fetchExternalIDs: { tmdbSeriesID in
                try await infoFetcher.tvSeriesExternalIDs(tmdbID: tmdbSeriesID)
            },
            lookupTVDBShowID: { tvdbID in
                try await tvMazeClient.lookupShowID(tvdbID: tvdbID)
            },
            lookupIMDbShowID: { imdbID in
                try await tvMazeClient.lookupShowID(imdbID: imdbID)
            },
            searchShowID: { title in
                try await tvMazeClient.searchShowID(named: title)
            },
            fetchShow: { tvMazeID in
                try await tvMazeClient.show(id: tvMazeID)
            }
        )
    }

    init(
        loadMappedShowID: @escaping @Sendable (Int) async throws -> Int?,
        fetchExternalIDs: @escaping @Sendable (Int) async throws -> TMDbSeriesExternalIDs,
        lookupTVDBShowID: @escaping @Sendable (Int) async throws -> Int?,
        lookupIMDbShowID: @escaping @Sendable (String) async throws -> Int?,
        searchShowID: @escaping @Sendable (String) async throws -> Int?,
        fetchShow: @escaping @Sendable (Int) async throws -> TVMazeShow?
    ) {
        self.loadMappedShowID = loadMappedShowID
        self.fetchExternalIDs = fetchExternalIDs
        self.lookupTVDBShowID = lookupTVDBShowID
        self.lookupIMDbShowID = lookupIMDbShowID
        self.searchShowID = searchShowID
        self.fetchShow = fetchShow
    }

    // MARK: - Automatic Resolution

    /// Resolves an eligible entry without performing title search.
    func resolve(entryType: AnimeType, tmdbID: Int) async throws -> TVMazeAutomaticResolution {
        guard let tmdbSeriesID = seriesTMDbID(entryType: entryType, tmdbID: tmdbID) else {
            return .ineligible
        }

        if let mappedShowID = try await loadMappedShowID(tmdbSeriesID),
            let show = try await fetchShow(mappedShowID)
        {
            return .resolved(show)
        }

        let externalIDs = try await fetchExternalIDs(tmdbSeriesID)

        if let tvdbID = externalIDs.tvdbID,
            let showID = try await lookupTVDBShowID(tvdbID),
            let show = try await fetchShow(showID)
        {
            return .resolved(show)
        }

        if let imdbID = externalIDs.imdbID,
            let showID = try await lookupIMDbShowID(imdbID),
            let show = try await fetchShow(showID)
        {
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
        guard let showID = try await searchShowID(title) else { return nil }
        return try await fetchShow(showID)
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
