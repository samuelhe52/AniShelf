import DataProvider
import Foundation

@MainActor
final class LibraryEntryConverter {
    private let repository: LibraryRepository

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func convertSeasonToSeries(_ entry: AnimeEntry, language: Language, fetcher: InfoFetcher) async throws {
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
            let parentLatestInfo = try await fetcher.latestInfo(
                entryType: .series,
                tmdbID: parentSeriesID,
                language: language
            )
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
        fetcher: InfoFetcher
    ) async throws {
        let parentSeriesID = entry.tmdbID
        libraryStoreLogger.info(
            "Converting series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")

        let userInfo = entry.userInfo
        let originalPosterURL = entry.posterURL
        let seasonTMDbID = entry.tmdbID

        async let parentLatestInfo = fetcher.latestInfo(
            entryType: .series,
            tmdbID: parentSeriesID,
            language: language
        )
        async let seasonLatestInfo = fetcher.latestInfo(
            entryType: .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID),
            tmdbID: seasonTMDbID,
            language: language
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
