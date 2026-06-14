//
//  AnimeEntryV2_8_0.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/13.
//

import Foundation
import SwiftData

extension SchemaV2_8_0 {
    @Model
    public final class AnimeEntry {
        public var name: String
        public var nameTranslations: [String: String] = [:]
        public var overview: String?
        public var overviewTranslations: [String: String] = [:]
        public var onAirDate: Date?
        public var type: AnimeType
        public var linkToDetails: URL?
        public var posterPath: String?
        public var backdropPath: String?
        public var customPosterPath: String?
        public var tmdbID: Int
        public var originalLanguageCode: String?

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryDetail.entry)
        public var detail: AnimeEntryDetail?

        public var parentSeriesEntry: AnimeEntry? = nil

        @Relationship(inverse: \AnimeEntry.parentSeriesEntry)
        public var childSeasonEntries: [AnimeEntry] = []

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryEpisodeProgress.entry)
        public var episodeProgresses: [AnimeEntryEpisodeProgress] = []

        public var onDisplay: Bool = true
        public var dateSaved: Date
        public var watchStatus: WatchStatus = WatchStatus.planToWatch
        public var dateStarted: Date?
        public var dateFinished: Date?
        public var isDateTrackingEnabled: Bool = true
        public var score: Int?
        public var favorite: Bool = false
        public var notes: String = ""
        public var usingCustomPoster: Bool = false

        public var libraryUpdatedAt: Date?
        public var trackingUpdatedAt: Date?

        public var selectedPosterPath: String? {
            usingCustomPoster ? customPosterPath : posterPath
        }

        public init(
            name: String,
            nameTranslations: [String: String] = [:],
            overview: String? = nil,
            overviewTranslations: [String: String] = [:],
            onAirDate: Date? = nil,
            type: AnimeType,
            linkToDetails: URL? = nil,
            posterPath: String? = nil,
            backdropPath: String? = nil,
            customPosterPath: String? = nil,
            posterURL: URL? = nil,
            backdropURL: URL? = nil,
            tmdbID: Int,
            originalLanguageCode: String? = nil,
            detail: AnimeEntryDetail? = nil,
            dateSaved: Date? = nil,
            dateStarted: Date? = nil,
            dateFinished: Date? = nil,
            isDateTrackingEnabled: Bool = true,
            score: Int? = nil,
            usingCustomPoster: Bool = false,
            libraryUpdatedAt: Date? = nil,
            trackingUpdatedAt: Date? = nil
        ) {
            self.name = name
            self.nameTranslations = nameTranslations
            self.overviewTranslations = overviewTranslations
            self.overview = overview
            self.onAirDate = onAirDate
            self.type = type
            self.linkToDetails = linkToDetails
            let resolvedPosterPath =
                TMDbImagePath.storagePath(from: posterPath, fallback: posterURL)
            let resolvedCustomPosterPath = TMDbImagePath.storagePath(from: customPosterPath)
            self.posterPath = resolvedPosterPath
            self.backdropPath =
                TMDbImagePath.storagePath(from: backdropPath, fallback: backdropURL)
            self.customPosterPath =
                usingCustomPoster
                ? resolvedCustomPosterPath ?? resolvedPosterPath
                : resolvedCustomPosterPath
            self.tmdbID = tmdbID
            self.originalLanguageCode = originalLanguageCode
            self.detail = detail
            self.dateSaved = dateSaved ?? .now
            self.dateStarted = dateStarted
            self.dateFinished = dateFinished
            self.isDateTrackingEnabled = isDateTrackingEnabled
            self.score = score
            self.usingCustomPoster = usingCustomPoster
            self.libraryUpdatedAt = libraryUpdatedAt
            self.trackingUpdatedAt = trackingUpdatedAt
        }

        public init(
            name: String,
            nameTranslations: [String: String],
            overview: String?,
            overviewTranslations: [String: String],
            onAirDate: Date?,
            type: AnimeType,
            linkToDetails: URL?,
            posterPath: String?,
            backdropPath: String?,
            customPosterPath: String?,
            tmdbID: Int,
            originalLanguageCode: String? = nil,
            detail: AnimeEntryDetail?,
            parentSeriesEntry: AnimeEntry?,
            episodeProgresses: [AnimeEntryEpisodeProgress] = [],
            onDisplay: Bool,
            watchStatus: WatchStatus,
            dateSaved: Date?,
            dateStarted: Date?,
            dateFinished: Date?,
            isDateTrackingEnabled: Bool,
            score: Int?,
            favorite: Bool,
            notes: String,
            usingCustomPoster: Bool,
            libraryUpdatedAt: Date? = nil,
            trackingUpdatedAt: Date? = nil
        ) {
            self.name = name
            self.nameTranslations = nameTranslations
            self.overviewTranslations = overviewTranslations
            self.overview = overview
            self.onAirDate = onAirDate
            self.type = type
            self.linkToDetails = linkToDetails
            self.posterPath = TMDbImagePath.storagePath(from: posterPath)
            self.backdropPath = TMDbImagePath.storagePath(from: backdropPath)
            self.customPosterPath = TMDbImagePath.storagePath(from: customPosterPath)
            self.tmdbID = tmdbID
            self.originalLanguageCode = originalLanguageCode
            self.detail = detail
            self.parentSeriesEntry = parentSeriesEntry
            self.onDisplay = onDisplay
            self.watchStatus = watchStatus
            self.dateSaved = dateSaved ?? .now
            self.dateStarted = dateStarted
            self.dateFinished = dateFinished
            self.isDateTrackingEnabled = isDateTrackingEnabled
            self.score = score
            self.favorite = favorite
            self.notes = notes
            self.usingCustomPoster = usingCustomPoster
            self.libraryUpdatedAt = libraryUpdatedAt
            self.trackingUpdatedAt = trackingUpdatedAt
            self.episodeProgresses = episodeProgresses
            episodeProgresses.forEach { $0.entry = self }
        }

        public enum WatchStatus: Equatable, CaseIterable, Codable, Sendable {
            case planToWatch
            case watching
            case watched
            case dropped
        }
    }
}
