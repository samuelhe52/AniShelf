//
//  CloudLibrarySyncClient.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import CloudKit
import DataProvider
import Foundation
import os

private let cloudLibrarySyncLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.CloudKit"
)

public struct CloudLibrarySyncClient: @unchecked Sendable {
    public static let defaultContainerIdentifier = "iCloud.com.samuelhe.MyAnimeList"
    public static let zoneName = "AniShelfLibrary"
    public static let recordType = "LibraryEntry"
    public static let subscriptionID = "AniShelfLibrary.zone"
    public static let recordZoneID = CKRecordZone.ID(
        zoneName: zoneName,
        ownerName: CKCurrentUserDefaultName
    )

    public let container: CKContainer?

    public var privateDatabase: CKDatabase? {
        container?.privateCloudDatabase
    }

    public var containerIdentifier: String? {
        container?.containerIdentifier ?? Bundle.main.bundleIdentifier
    }

    public init(container: CKContainer? = nil) {
        self.container = container
    }

    public func recordID(for identity: LibraryEntrySyncIdentity) -> CKRecord.ID {
        CKRecord.ID(recordName: identity.rawID, zoneID: Self.recordZoneID)
    }

    public func changeTokenNamespace(
        accountRecordID: CKRecord.ID
    ) -> CloudLibrarySyncChangeTokenStore.Namespace? {
        guard let containerIdentifier else { return nil }
        return .init(
            containerIdentifier: containerIdentifier,
            accountIdentifier: accountRecordID.recordName
        )
    }

    public func changeTokenNamespace() async throws -> CloudLibrarySyncChangeTokenStore.Namespace? {
        guard let container else { return nil }
        let accountRecordID = try await container.userRecordID()
        return changeTokenNamespace(accountRecordID: accountRecordID)
    }

    public func record(from snapshot: LibraryEntrySyncSnapshot) throws -> CKRecord {
        let identity = try Self.validatedIdentity(
            recordName: snapshot.identity.rawID,
            entryTypeValue: snapshot.entryType.cloudKitValue,
            tmdbID: snapshot.tmdbID,
            parentSeriesID: snapshot.parentSeriesID,
            seasonNumber: snapshot.seasonNumber
        )

        let record = CKRecord(recordType: Self.recordType, recordID: recordID(for: identity))
        record[Field.schemaVersion] = LibraryEntrySyncSnapshot.currentSchemaVersion
        record[Field.tmdbID] = snapshot.tmdbID
        record[Field.entryType] = snapshot.entryType.cloudKitValue
        record[Field.parentSeriesID] = snapshot.parentSeriesID
        record[Field.seasonNumber] = snapshot.seasonNumber
        record[Field.onDisplay] = snapshot.onDisplay
        record[Field.dateSaved] = snapshot.dateSaved
        record[Field.watchStatus] = snapshot.watchStatus.cloudKitValue
        record[Field.dateStarted] = snapshot.dateStarted
        record[Field.dateFinished] = snapshot.dateFinished
        record[Field.isDateTrackingEnabled] = snapshot.isDateTrackingEnabled
        record[Field.score] = snapshot.score
        record[Field.favorite] = snapshot.favorite
        record[Field.notes] = snapshot.notes
        record[Field.usingCustomPoster] = snapshot.usingCustomPoster
        record[Field.customPosterURL] = snapshot.usingCustomPoster ? snapshot.customPosterURL?.absoluteString : nil
        record[Field.episodeProgresses] = try Self.encodeEpisodeProgresses(snapshot.episodeProgresses)
        record[Field.libraryUpdatedAt] = snapshot.libraryUpdatedAt
        record[Field.trackingUpdatedAt] = snapshot.trackingUpdatedAt
        record[Field.deletedAt] = snapshot.deletedAt
        return record
    }

    public func snapshot(from record: CKRecord) throws -> LibraryEntrySyncSnapshot {
        do {
            return try decodedSnapshot(from: record)
        } catch let error as CloudLibrarySyncDecodeError {
            Self.logDecodeFailure(error, record: record)
            throw error
        }
    }

    private func decodedSnapshot(from record: CKRecord) throws -> LibraryEntrySyncSnapshot {
        guard record.recordType == Self.recordType else {
            throw CloudLibrarySyncDecodeError.wrongRecordType(actual: record.recordType)
        }

        let schemaVersion: Int = try Self.requiredValue(for: Field.schemaVersion, in: record)
        guard schemaVersion <= LibraryEntrySyncSnapshot.currentSchemaVersion else {
            throw CloudLibrarySyncDecodeError.unsupportedSchemaVersion(schemaVersion)
        }

        let tmdbID: Int = try Self.requiredValue(for: Field.tmdbID, in: record)
        let entryTypeValue: String = try Self.requiredValue(for: Field.entryType, in: record)
        let parentSeriesID: Int? = try Self.optionalValue(for: Field.parentSeriesID, in: record)
        let seasonNumber: Int? = try Self.optionalValue(for: Field.seasonNumber, in: record)
        let entryType = try Self.entryType(
            recordName: record.recordID.recordName,
            entryTypeValue: entryTypeValue,
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber
        )
        let identity = try Self.validatedIdentity(
            recordName: record.recordID.recordName,
            entryTypeValue: entryTypeValue,
            tmdbID: tmdbID,
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber
        )

        let onDisplay: Bool = try Self.requiredValue(for: Field.onDisplay, in: record)
        let dateSaved: Date = try Self.requiredValue(for: Field.dateSaved, in: record)
        let watchStatusValue: String = try Self.requiredValue(for: Field.watchStatus, in: record)
        guard let watchStatus = AnimeEntry.WatchStatus(cloudKitValue: watchStatusValue) else {
            throw CloudLibrarySyncDecodeError.invalidEnumValue(field: Field.watchStatus)
        }

        let dateStarted: Date? = try Self.optionalValue(for: Field.dateStarted, in: record)
        let dateFinished: Date? = try Self.optionalValue(for: Field.dateFinished, in: record)
        let isDateTrackingEnabled: Bool = try Self.requiredValue(
            for: Field.isDateTrackingEnabled,
            in: record
        )
        let score: Int? = try Self.optionalValue(for: Field.score, in: record)
        let favorite: Bool = try Self.requiredValue(for: Field.favorite, in: record)
        let notes: String = try Self.requiredValue(for: Field.notes, in: record)
        let usingCustomPoster: Bool = try Self.requiredValue(for: Field.usingCustomPoster, in: record)
        let customPosterURL = try Self.customPosterURL(from: record)
        let episodeProgressData: Data = try Self.requiredValue(for: Field.episodeProgresses, in: record)
        let libraryUpdatedAt: Date? = try Self.optionalValue(for: Field.libraryUpdatedAt, in: record)
        let trackingUpdatedAt: Date? = try Self.optionalValue(for: Field.trackingUpdatedAt, in: record)
        let deletedAt: Date? = try Self.optionalValue(for: Field.deletedAt, in: record)

        return try LibraryEntrySyncSnapshot(
            schemaVersion: schemaVersion,
            identity: identity,
            tmdbID: tmdbID,
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber,
            entryType: entryType,
            onDisplay: onDisplay,
            dateSaved: dateSaved,
            watchStatus: watchStatus,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            isDateTrackingEnabled: isDateTrackingEnabled,
            score: score,
            favorite: favorite,
            notes: notes,
            usingCustomPoster: usingCustomPoster,
            customPosterURL: customPosterURL,
            episodeProgresses: Self.decodeEpisodeProgresses(episodeProgressData),
            libraryUpdatedAt: libraryUpdatedAt,
            trackingUpdatedAt: trackingUpdatedAt,
            deletedAt: deletedAt
        )
    }

    private static func logDecodeFailure(_ error: CloudLibrarySyncDecodeError, record: CKRecord) {
        switch error {
        case .wrongRecordType(let actual):
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure reason=wrongRecordType expectedRecordType=\(Self.recordType, privacy: .public) actualRecordType=\(actual, privacy: .public)"
            )
        case .unsupportedSchemaVersion(let schemaVersion):
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure recordType=\(record.recordType, privacy: .public) field=\(Field.schemaVersion, privacy: .public) reason=unsupportedSchemaVersion schemaVersion=\(schemaVersion, privacy: .public)"
            )
        case .missingRequiredField(let field):
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure recordType=\(record.recordType, privacy: .public) field=\(field, privacy: .public) reason=missingRequiredField"
            )
        case .invalidScalarValue(let field):
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure recordType=\(record.recordType, privacy: .public) field=\(field, privacy: .public) reason=invalidScalarValue"
            )
        case .invalidEnumValue(let field):
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure recordType=\(record.recordType, privacy: .public) field=\(field, privacy: .public) reason=invalidEnumValue"
            )
        case .invalidIdentityCombination(let recordName):
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure recordType=\(record.recordType, privacy: .public) field=identity reason=invalidIdentityCombination recordName=\(recordName, privacy: .private)"
            )
        case .corruptEpisodeProgressPayload:
            cloudLibrarySyncLogger.error(
                "operation=decodeSnapshot result=failure recordType=\(record.recordType, privacy: .public) field=\(Field.episodeProgresses, privacy: .public) reason=corruptEpisodeProgressPayload"
            )
        }
    }
}

extension CloudLibrarySyncClient {
    fileprivate enum Field {
        fileprivate static let schemaVersion = "schemaVersion"
        fileprivate static let tmdbID = "tmdbID"
        fileprivate static let parentSeriesID = "parentSeriesID"
        fileprivate static let seasonNumber = "seasonNumber"
        fileprivate static let entryType = "entryType"
        fileprivate static let onDisplay = "onDisplay"
        fileprivate static let dateSaved = "dateSaved"
        fileprivate static let watchStatus = "watchStatus"
        fileprivate static let dateStarted = "dateStarted"
        fileprivate static let dateFinished = "dateFinished"
        fileprivate static let isDateTrackingEnabled = "isDateTrackingEnabled"
        fileprivate static let score = "score"
        fileprivate static let favorite = "favorite"
        fileprivate static let notes = "notes"
        fileprivate static let usingCustomPoster = "usingCustomPoster"
        fileprivate static let customPosterURL = "customPosterURL"
        fileprivate static let episodeProgresses = "episodeProgresses"
        fileprivate static let libraryUpdatedAt = "libraryUpdatedAt"
        fileprivate static let trackingUpdatedAt = "trackingUpdatedAt"
        fileprivate static let deletedAt = "deletedAt"
    }

    fileprivate static func requiredValue<T>(for field: String, in record: CKRecord) throws -> T {
        if let value = record[field] as? T {
            return value
        }
        if record.allKeys().contains(field) {
            throw CloudLibrarySyncDecodeError.invalidScalarValue(field: field)
        }
        throw CloudLibrarySyncDecodeError.missingRequiredField(field)
    }

    fileprivate static func optionalValue<T>(for field: String, in record: CKRecord) throws -> T? {
        guard let rawValue = record[field] else { return nil }
        guard let value = rawValue as? T else {
            throw CloudLibrarySyncDecodeError.invalidScalarValue(field: field)
        }
        return value
    }

    fileprivate static func entryType(
        recordName: String,
        entryTypeValue: String,
        parentSeriesID: Int?,
        seasonNumber: Int?
    ) throws -> AnimeType {
        guard let kind = EntryType(rawValue: entryTypeValue) else {
            throw CloudLibrarySyncDecodeError.invalidEnumValue(field: Field.entryType)
        }

        switch kind {
        case .movie:
            guard parentSeriesID == nil, seasonNumber == nil else {
                throw CloudLibrarySyncDecodeError.invalidIdentityCombination(recordName: recordName)
            }
            return .movie
        case .series:
            guard parentSeriesID == nil, seasonNumber == nil else {
                throw CloudLibrarySyncDecodeError.invalidIdentityCombination(recordName: recordName)
            }
            return .series
        case .season:
            guard let parentSeriesID, let seasonNumber else {
                throw CloudLibrarySyncDecodeError.invalidIdentityCombination(recordName: recordName)
            }
            return .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID)
        }
    }

    fileprivate static func validatedIdentity(
        recordName: String,
        entryTypeValue: String,
        tmdbID: Int,
        parentSeriesID: Int?,
        seasonNumber: Int?
    ) throws -> LibraryEntrySyncIdentity {
        let entryType = try entryType(
            recordName: recordName,
            entryTypeValue: entryTypeValue,
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber
        )
        let identity = LibraryEntrySyncIdentity(entryType: entryType, tmdbID: tmdbID)
        guard identity.rawID == recordName else {
            throw CloudLibrarySyncDecodeError.invalidIdentityCombination(recordName: recordName)
        }
        return identity
    }

    fileprivate static func customPosterURL(from record: CKRecord) throws -> URL? {
        guard let value = record[Field.customPosterURL] else { return nil }
        guard let rawURL = value as? String, let url = URL(string: rawURL) else {
            throw CloudLibrarySyncDecodeError.invalidScalarValue(field: Field.customPosterURL)
        }
        return url
    }

    fileprivate static func encodeEpisodeProgresses(
        _ progresses: [LibraryEntrySyncSnapshot.EpisodeProgress]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(progresses)
    }

    fileprivate static func decodeEpisodeProgresses(
        _ data: Data
    ) throws -> [LibraryEntrySyncSnapshot.EpisodeProgress] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([LibraryEntrySyncSnapshot.EpisodeProgress].self, from: data)
        } catch {
            throw CloudLibrarySyncDecodeError.corruptEpisodeProgressPayload
        }
    }

    fileprivate enum EntryType: String {
        case movie
        case series
        case season
    }
}

extension AnimeType {
    fileprivate var cloudKitValue: String {
        switch self {
        case .movie:
            CloudLibrarySyncClient.EntryType.movie.rawValue
        case .series:
            CloudLibrarySyncClient.EntryType.series.rawValue
        case .season:
            CloudLibrarySyncClient.EntryType.season.rawValue
        }
    }
}

extension AnimeEntry.WatchStatus {
    fileprivate init?(cloudKitValue: String) {
        switch cloudKitValue {
        case "planToWatch":
            self = .planToWatch
        case "watching":
            self = .watching
        case "watched":
            self = .watched
        case "dropped":
            self = .dropped
        default:
            return nil
        }
    }

    fileprivate var cloudKitValue: String {
        switch self {
        case .planToWatch:
            "planToWatch"
        case .watching:
            "watching"
        case .watched:
            "watched"
        case .dropped:
            "dropped"
        }
    }
}
