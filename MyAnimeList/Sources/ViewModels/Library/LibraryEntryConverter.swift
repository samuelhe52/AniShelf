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
        fetcher: InfoFetcher,
        latestInfoFetcher: LibraryEntryLatestInfoFetcher? = nil
    ) async throws {
        guard case .season(_, let parentSeriesID) = entry.type else { return }
        let seasonTMDbID = entry.tmdbID
        libraryStoreLogger.info(
            "Converting season \(seasonTMDbID, privacy: .public) to series \(parentSeriesID, privacy: .public)")

        let userInfo = entry.userInfo
        let originalPosterURL = entry.posterURL

        let parentEntry: AnimeEntry
        if let existingParent = entry.parentSeriesEntry {
            parentEntry = existingParent
            parentEntry.updateDisplayState(true)
        } else {
            let resolveLatestInfo = latestInfoFetcher ?? { entryType, tmdbID, language in
                try await fetcher.latestInfo(
                    entryType: entryType,
                    tmdbID: tmdbID,
                    language: language
                )
            }
            let parentLatestInfo = try await resolveLatestInfo(.series, parentSeriesID, language)
            parentEntry = AnimeEntry(fromInfo: parentLatestInfo.0)
            parentEntry.replaceDetail(from: parentLatestInfo.1)
            parentEntry.updateDisplayState(true)
            try repository.newEntry(parentEntry)
        }

        parentEntry.updateUserInfoFromUserAction(userInfo)
        if userInfo.usingCustomPoster {
            parentEntry.updateCustomPosterURL(originalPosterURL)
        }

        try repository.deleteEntry(entry)

        libraryStoreLogger.info(
            "Converted season \(seasonTMDbID, privacy: .public) to series \(parentSeriesID, privacy: .public)")
    }

    func convertSeriesToSeason(
        _ entry: AnimeEntry,
        seasonNumber: Int,
        language: Language,
        fetcher: InfoFetcher,
        latestInfoFetcher: LibraryEntryLatestInfoFetcher? = nil
    ) async throws {
        let parentSeriesID = entry.tmdbID
        libraryStoreLogger.info(
            "Converting series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")

        let userInfo = entry.userInfo
        let originalPosterURL = entry.posterURL
        let seasonTMDbID = entry.tmdbID
        let resolveLatestInfo = latestInfoFetcher ?? { entryType, tmdbID, language in
            try await fetcher.latestInfo(
                entryType: entryType,
                tmdbID: tmdbID,
                language: language
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

        try repository.deleteEntry(entry)

        let parentEntry = AnimeEntry(fromInfo: resolvedParentLatestInfo.0)
        parentEntry.replaceDetail(from: resolvedParentLatestInfo.1)
        parentEntry.updateDisplayState(false)

        let seasonEntry = AnimeEntry(fromInfo: resolvedSeasonLatestInfo.0)
        seasonEntry.replaceDetail(from: resolvedSeasonLatestInfo.1)
        seasonEntry.parentSeriesEntry = parentEntry
        seasonEntry.updateDisplayState(true)
        seasonEntry.updateUserInfoFromUserAction(userInfo)
        if userInfo.usingCustomPoster {
            seasonEntry.updateCustomPosterURL(originalPosterURL)
        }

        try repository.newEntry(parentEntry)
        try repository.newEntry(seasonEntry)

        libraryStoreLogger.info(
            "Converted series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")
    }
}
