//
//  LibraryEntryConverter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/7.
//

import DataProvider
import Foundation

typealias LibraryEntryLatestInfoFetcher =
    @Sendable (AnimeType, Int, Language) async throws -> (EntryMetadata, AnimeEntryDetailDTO)

@MainActor
final class LibraryEntryConverter {
    private let repository: LibraryRepository

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func convertSeasonToSeries(
        _ entry: AnimeEntry,
        language: Language,
        posterLanguage: PosterLanguagePreference,
        fetcher: InfoFetcher,
        latestInfoFetcher: LibraryEntryLatestInfoFetcher? = nil
    ) async throws {
        guard case .season(_, let parentSeriesID) = entry.type else { return }
        let seasonTMDbID = entry.tmdbID
        libraryStoreLogger.info(
            "Converting season \(seasonTMDbID, privacy: .public) to series \(parentSeriesID, privacy: .public)")

        let userInfo = entry.userInfo
        let categoryIDs = entry.categoryIDs
        let originalPosterURL = entry.posterURL

        let parentEntry: AnimeEntry
        let entriesToInsert: [AnimeEntry]
        if let existingParent = entry.parentSeriesEntry {
            parentEntry = existingParent
            parentEntry.updateDisplayState(true)
            entriesToInsert = []
        } else {
            let resolveLatestInfo =
                latestInfoFetcher ?? { entryType, tmdbID, language in
                    try await fetcher.latestInfo(
                        entryType: entryType,
                        tmdbID: tmdbID,
                        language: language,
                        posterLanguage: posterLanguage
                    )
                }
            let parentLatestInfo = try await resolveLatestInfo(.series, parentSeriesID, language)
            parentEntry = AnimeEntry(fromInfo: parentLatestInfo.0)
            parentEntry.replaceDetail(from: parentLatestInfo.1)
            parentEntry.updateDisplayState(true)
            entriesToInsert = [parentEntry]
        }

        // Episode notes already live on the parent; keep its other seasons intact.
        var seriesUserInfo = userInfo
        seriesUserInfo.episodeNotes = parentEntry.episodeNotes
        parentEntry.updateUserInfoFromUserAction(seriesUserInfo)
        parentEntry.updateCategoryIDs(categoryIDs)
        if userInfo.usingCustomPoster {
            parentEntry.updateCustomPosterURL(originalPosterURL)
        }

        try repository.replaceEntry(entry, inserting: entriesToInsert)

        libraryStoreLogger.info(
            "Converted season \(seasonTMDbID, privacy: .public) to series \(parentSeriesID, privacy: .public)")
    }

    func convertSeriesToSeason(
        _ entry: AnimeEntry,
        seasonNumber: Int,
        language: Language,
        posterLanguage: PosterLanguagePreference,
        fetcher: InfoFetcher,
        latestInfoFetcher: LibraryEntryLatestInfoFetcher? = nil
    ) async throws {
        let parentSeriesID = entry.tmdbID
        libraryStoreLogger.info(
            "Converting series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")

        let userInfo = entry.userInfo
        let categoryIDs = entry.categoryIDs
        let originalPosterURL = entry.posterURL
        let seasonTMDbID = entry.tmdbID
        let resolveLatestInfo =
            latestInfoFetcher ?? { entryType, tmdbID, language in
                try await fetcher.latestInfo(
                    entryType: entryType,
                    tmdbID: tmdbID,
                    language: language,
                    posterLanguage: posterLanguage
                )
            }

        async let parentLatestInfo = resolveLatestInfo(.series, parentSeriesID, language)
        async let seasonLatestInfo = resolveLatestInfo(
            .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID),
            seasonTMDbID,
            language
        )
        let resolvedParentLatestInfo = try await parentLatestInfo
        let resolvedSeasonLatestInfo = try await seasonLatestInfo

        let parentEntry = AnimeEntry(fromInfo: resolvedParentLatestInfo.0)
        parentEntry.replaceDetail(from: resolvedParentLatestInfo.1)
        parentEntry.updateDisplayState(false)
        parentEntry.storedEpisodeNotes = entry.episodeNotes

        let seasonEntry = AnimeEntry(fromInfo: resolvedSeasonLatestInfo.0)
        seasonEntry.replaceDetail(from: resolvedSeasonLatestInfo.1)
        seasonEntry.parentSeriesEntry = parentEntry
        seasonEntry.updateDisplayState(true)
        // The parent already holds the current notes; replaying the pre-fetch snapshot
        // would revert note edits received while metadata loaded.
        var seasonUserInfo = userInfo
        seasonUserInfo.episodeNotes = seasonEntry.episodeNotes
        seasonEntry.updateUserInfoFromUserAction(seasonUserInfo)
        seasonEntry.updateCategoryIDs(categoryIDs)
        if userInfo.usingCustomPoster {
            seasonEntry.updateCustomPosterURL(originalPosterURL)
        }

        try repository.replaceEntry(entry, inserting: [parentEntry, seasonEntry])

        libraryStoreLogger.info(
            "Converted series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")
    }
}
