//
//  AnimeEntryV2_6_0Legacy.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/5.
//

import Foundation
import SwiftData

extension SchemaV2_6_0Legacy {
    /// Recovery-only representation of entries written by the released V2.6.0 model.
    @Model
    final class AnimeEntry {
        var name: String
        var nameTranslations: [String: String] = [:]
        var overview: String?
        var overviewTranslations: [String: String] = [:]
        var onAirDate: Date?
        var type: AnimeType
        var linkToDetails: URL?
        var posterURL: URL?
        var backdropURL: URL?
        var tmdbID: Int
        var detail: LegacyAnimeEntryDetailPayloadV2_6_0?
        var parentSeriesEntry: AnimeEntry? = nil

        @Relationship(inverse: \AnimeEntry.parentSeriesEntry)
        var childSeasonEntries: [AnimeEntry] = []

        var onDisplay: Bool = true
        var dateSaved: Date
        var watchStatus: WatchStatus = WatchStatus.planToWatch
        var dateStarted: Date?
        var dateFinished: Date?
        var favorite: Bool = false
        var notes: String = ""
        var usingCustomPoster: Bool = false

        enum WatchStatus: Equatable, CaseIterable, Codable {
            case planToWatch
            case watching
            case watched
            case dropped
        }

        init(
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
            detail: LegacyAnimeEntryDetailPayloadV2_6_0? = nil,
            dateSaved: Date? = nil,
            dateStarted: Date? = nil,
            dateFinished: Date? = nil,
            usingCustomPoster: Bool = false
        ) {
            self.name = name
            self.nameTranslations = nameTranslations
            self.overview = overview
            self.overviewTranslations = overviewTranslations
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
            self.usingCustomPoster = usingCustomPoster
        }
    }
}

extension AnimeEntryMigrationWatchStatus {
    init(_ status: SchemaV2_6_0Legacy.AnimeEntry.WatchStatus) {
        switch status {
        case .planToWatch: self = .planToWatch
        case .watching: self = .watching
        case .watched: self = .watched
        case .dropped: self = .dropped
        }
    }
}

extension SchemaV2_6_0Legacy.AnimeEntry {
    func migrationDTO(index: Int) -> AnimeEntryMigrationDTO {
        AnimeEntryMigrationDTO(
            originalIndex: index,
            oldID: persistentModelID,
            parentSeriesOldID: parentSeriesEntry?.persistentModelID,
            name: name,
            nameTranslations: nameTranslations,
            overview: overview,
            overviewTranslations: overviewTranslations,
            onAirDate: onAirDate,
            type: type,
            linkToDetails: linkToDetails,
            posterURL: posterURL,
            backdropURL: backdropURL,
            tmdbID: tmdbID,
            detail: detail.map(AnimeEntryDetailDTO.init(fromV260Legacy:)),
            onDisplay: onDisplay,
            watchStatus: .init(watchStatus),
            dateSaved: dateSaved,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            score: nil,
            favorite: favorite,
            notes: notes,
            usingCustomPoster: usingCustomPoster
        )
    }
}
