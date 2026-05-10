//
//  AnimeEntryV2_7_3.swift
//  DataProvider
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import SwiftData

extension SchemaV2_7_3 {
    @Model
    public final class AnimeEntry {
        public var name: String
        public var nameTranslations: [String: String] = [:]
        public var overview: String?
        public var overviewTranslations: [String: String] = [:]
        public var onAirDate: Date?
        public var type: AnimeType
        public var linkToDetails: URL?
        public var posterURL: URL?
        public var backdropURL: URL?
        public var tmdbID: Int

        @Relationship(deleteRule: .cascade, inverse: \AnimeEntryDetail.entry)
        public var detail: AnimeEntryDetail?

        public var parentSeriesEntry: AnimeEntry? = nil

        @Relationship(inverse: \AnimeEntry.parentSeriesEntry)
        public var childSeasonEntries: [AnimeEntry] = []

        public var onDisplay: Bool = true
        public var dateSaved: Date
        public var watchStatus: WatchStatus = WatchStatus.planToWatch
        public var dateStarted: Date?
        public var dateFinished: Date?
        public var score: Int?
        public var favorite: Bool = false
        public var notes: String = ""
        public var usingCustomPoster: Bool = false

        public init(
            name: String,
            nameTranslations: [String: String] = [:],
            overview: String? = nil,
            overviewTranslations: [String: String] = [:],
            onAirDate: Date? = nil,
            type: AnimeType,
            linkToDetails: URL? = nil,
            posterURL: URL? = nil,
            backdropURL: URL? = nil,
            tmdbID: Int,
            detail: AnimeEntryDetail? = nil,
            dateSaved: Date? = nil,
            dateStarted: Date? = nil,
            dateFinished: Date? = nil,
            score: Int? = nil,
            usingCustomPoster: Bool = false
        ) {
            self.name = name
            self.nameTranslations = nameTranslations
            self.overviewTranslations = overviewTranslations
            self.overview = overview
            self.onAirDate = onAirDate
            self.type = type
            self.linkToDetails = linkToDetails
            self.posterURL = posterURL
            self.backdropURL = backdropURL
            self.tmdbID = tmdbID
            self.detail = detail
            self.dateSaved = dateSaved ?? .now
            self.dateStarted = dateStarted
            self.dateFinished = dateFinished
            self.score = score
            self.usingCustomPoster = usingCustomPoster
        }

        public init(
            name: String,
            nameTranslations: [String: String],
            overview: String?,
            overviewTranslations: [String: String],
            onAirDate: Date?,
            type: AnimeType,
            linkToDetails: URL?,
            posterURL: URL?,
            backdropURL: URL?,
            tmdbID: Int,
            detail: AnimeEntryDetail?,
            parentSeriesEntry: AnimeEntry?,
            onDisplay: Bool,
            watchStatus: WatchStatus,
            dateSaved: Date?,
            dateStarted: Date?,
            dateFinished: Date?,
            score: Int?,
            favorite: Bool,
            notes: String,
            usingCustomPoster: Bool
        ) {
            self.name = name
            self.nameTranslations = nameTranslations
            self.overviewTranslations = overviewTranslations
            self.overview = overview
            self.onAirDate = onAirDate
            self.type = type
            self.linkToDetails = linkToDetails
            self.posterURL = posterURL
            self.backdropURL = backdropURL
            self.tmdbID = tmdbID
            self.detail = detail
            self.parentSeriesEntry = parentSeriesEntry
            self.onDisplay = onDisplay
            self.watchStatus = watchStatus
            self.dateSaved = dateSaved ?? .now
            self.dateStarted = dateStarted
            self.dateFinished = dateFinished
            self.score = score
            self.favorite = favorite
            self.notes = notes
            self.usingCustomPoster = usingCustomPoster
        }

        public enum WatchStatus: Equatable, CaseIterable, Codable {
            case planToWatch
            case watching
            case watched
            case dropped
        }
    }
}
