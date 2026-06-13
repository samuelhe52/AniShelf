//
//  AnimeEntry+Extensions.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/29.
//

import DataProvider
import Foundation

extension AnimeEntry {
    /// Creates a new AnimeEntry instance from EntryMetadata.
    ///
    /// - Parameter info: The EntryMetadata containing the anime details.
    convenience init(fromInfo info: EntryMetadata) {
        self.init(
            name: info.name,
            nameTranslations: info.nameTranslations,
            overview: info.overview,
            overviewTranslations: info.overviewTranslations,
            onAirDate: info.onAirDate,
            type: info.type,
            linkToDetails: info.linkToDetails,
            posterPath: info.posterPath,
            backdropPath: info.backdropPath,
            tmdbID: info.tmdbID,
            originalLanguageCode: info.originalLanguageCode,
            dateSaved: .now)
    }

    /// Updates the anime entry with new information from EntryMetadata.
    ///
    /// - Parameter info: The EntryMetadata containing updated anime details.
    /// - Note: Only updates properties that have non-nil values in the info parameter.
    func update(from info: EntryMetadata) {
        name = info.name
        nameTranslations =
            info.nameTranslations.isEmpty ? self.nameTranslations : info.nameTranslations
        overview = info.overview ?? self.overview
        overviewTranslations =
            info.overviewTranslations.isEmpty
            ? self.overviewTranslations : info.overviewTranslations
        linkToDetails = info.linkToDetails ?? self.linkToDetails
        posterPath = info.posterPath ?? self.posterPath
        backdropPath = info.backdropPath ?? self.backdropPath
        onAirDate = info.onAirDate ?? self.onAirDate
        type = info.type
        tmdbID = info.tmdbID
        originalLanguageCode = info.originalLanguageCode
    }

    /// Replaces remote metadata during an explicit refresh.
    ///
    /// Unlike `update(from:)`, this method intentionally clears fields that TMDb no longer returns.
    /// User-owned state is not touched; callers can preserve custom poster choices by passing `true`.
    func replaceMetadata(from info: EntryMetadata, preservingCustomPoster: Bool) {
        name = info.name
        nameTranslations = info.nameTranslations
        overview = info.overview
        overviewTranslations = info.overviewTranslations
        linkToDetails = info.linkToDetails
        posterPath = info.posterPath
        if !preservingCustomPoster {
            customPosterPath = nil
            usingCustomPoster = false
        }
        backdropPath = info.backdropPath
        onAirDate = info.onAirDate
        type = info.type
        tmdbID = info.tmdbID
        originalLanguageCode = info.originalLanguageCode
    }

    /// Converts the AnimeEntry to EntryMetadata.
    var entryMetadata: EntryMetadata {
        EntryMetadata(
            name: name,
            nameTranslations: nameTranslations,
            overview: overview,
            overviewTranslations: overviewTranslations,
            posterPath: posterPath,
            backdropPath: backdropPath,
            originalLanguageCode: originalLanguageCode,
            tmdbID: tmdbID,
            onAirDate: onAirDate,
            linkToDetails: linkToDetails,
            type: type)
    }

    /// An overview that automatically fallbacks to the parent series' overview if the season's overview is nil or empty.
    var displayOverview: String? {
        if let overview, !overview.isEmpty {
            return overview
        } else if let parentSeriesOverview = parentSeriesEntry?.overview {
            return parentSeriesOverview
        } else {
            return nil
        }
    }

    /// A name that defaults to the parent series' name if the current entry is a `.season`.
    var displayName: String {
        parentSeriesEntry?.name ?? name
    }

    /// Generates a hidden entry from a given parentSeriesID.
    static func generateParentSeriesEntryForSeason(
        parentSeriesID: Int,
        fetcher: InfoFetcher,
        infoLanguage language: Language
    ) async throws -> sending AnimeEntry {
        let parentSeriesInfo = try await fetcher.tvSeriesInfo(
            tmdbID: parentSeriesID, language: language)
        let parentSeriesEntry = AnimeEntry(fromInfo: parentSeriesInfo)
        parentSeriesEntry.setDisplayState(false)
        return parentSeriesEntry
    }

    var userInfo: UserEntryInfo {
        UserEntryInfo(from: self)
    }

    /// Resolves fields that library UI snapshots may still read while SwiftData is processing deletion.
    func resolveLibraryDisplayFaultsBeforeDeletion() {
        _ = name
        _ = parentSeriesEntry?.name
        _ = overview
        _ = parentSeriesEntry?.overview
        _ = onAirDate
        _ = type
        _ = posterPath
        _ = backdropPath
        _ = tmdbID
        _ = watchStatus
        _ = favorite
        _ = score
        _ = dateSaved
        _ = dateStarted
        _ = dateFinished
        _ = isDateTrackingEnabled

        if let detail {
            _ = detail.runtimeMinutes
            _ = detail.episodeCount
            _ = detail.logoImagePath
            _ = detail.characters
            _ = detail.staff
            _ = detail.seasons
            _ = detail.episodes
        }
    }

    func userInfoHasChanges(comparedTo compared: UserEntryInfo) -> Bool {
        !userInfo.isSemanticallyEquivalent(to: compared)
    }

}
