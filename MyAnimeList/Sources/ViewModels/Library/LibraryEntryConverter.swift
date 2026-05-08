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
            parentEntry.onDisplay = true
        } else {
            let parentInfo = try await fetcher.tvSeriesInfo(tmdbID: parentSeriesID, language: language)
            parentEntry = AnimeEntry(fromInfo: parentInfo)
            parentEntry.replaceDetail(
                from: try await fetcher.detailInfo(
                    entryType: .series,
                    tmdbID: parentSeriesID,
                    language: language
                ))
            parentEntry.onDisplay = true
            try repository.newEntry(parentEntry)
        }

        parentEntry.updateUserInfo(from: userInfo)
        if userInfo.usingCustomPoster {
            parentEntry.posterURL = originalPosterURL
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

        async let parentInfo = fetcher.tvSeriesInfo(tmdbID: parentSeriesID, language: language)
        async let parentDetail = fetcher.detailInfo(
            entryType: .series,
            tmdbID: parentSeriesID,
            language: language
        )
        async let seasonInfo = fetcher.tvSeasonInfo(
            seasonNumber: seasonNumber,
            parentSeriesID: parentSeriesID,
            language: language)
        async let seasonDetail = fetcher.detailInfo(
            entryType: .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID),
            tmdbID: seasonTMDbID,
            language: language
        )
        let resolvedParentInfo = try await parentInfo
        var resolvedSeasonInfo = try await seasonInfo

        try repository.deleteEntry(entry)

        if userInfo.usingCustomPoster {
            resolvedSeasonInfo.posterURL = originalPosterURL
        }

        let parentEntry = AnimeEntry(fromInfo: resolvedParentInfo)
        parentEntry.replaceDetail(from: try await parentDetail)
        parentEntry.onDisplay = false

        let seasonEntry = AnimeEntry(fromInfo: resolvedSeasonInfo)
        seasonEntry.replaceDetail(from: try await seasonDetail)
        seasonEntry.parentSeriesEntry = parentEntry
        seasonEntry.updateUserInfo(from: userInfo)
        if userInfo.usingCustomPoster {
            seasonEntry.posterURL = originalPosterURL
        }

        try repository.newEntry(parentEntry)
        try repository.newEntry(seasonEntry)

        libraryStoreLogger.info(
            "Converted series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")
    }
}
