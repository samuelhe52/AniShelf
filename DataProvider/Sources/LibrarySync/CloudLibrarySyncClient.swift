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

fileprivate let cloudLibrarySyncLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.CloudKit"
)

/// Converts AniShelf sync changes to and from CloudKit records.
///
/// `CloudLibrarySyncClient` owns the stable CloudKit schema constants and the
/// validation rules that keep record names, entry types, and season identifiers
/// aligned with `LibraryEntrySyncIdentity`.
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

    /// Private CloudKit database used for user library sync.
    public var privateDatabase: CKDatabase? {
        container?.privateCloudDatabase
    }

    /// Identifier used to namespace persisted change tokens.
    public var containerIdentifier: String? {
        container?.containerIdentifier ?? Bundle.main.bundleIdentifier
    }

    /// Creates a client for a CloudKit container.
    ///
    /// - Parameter container: CloudKit container to use. Pass `nil` in tests or
    ///   when sync is intentionally disabled.
    public init(container: CKContainer? = nil) {
        self.container = container
    }

    /// Returns the CloudKit record ID for a sync identity in AniShelf's library zone.
    public func recordID(for identity: LibraryEntrySyncIdentity) -> CKRecord.ID {
        CKRecord.ID(recordName: identity.rawID, zoneID: Self.recordZoneID)
    }

    /// Builds the change-token namespace for the active container/account pair.
    ///
    /// - Parameter accountRecordID: CloudKit user record ID for the currently
    ///   signed-in iCloud account.
    /// - Returns: A namespace suitable for `CloudLibrarySyncChangeTokenStore`,
    ///   or `nil` when the container identity cannot be determined.
    public func changeTokenNamespace(
        accountRecordID: CKRecord.ID
    ) -> CloudLibrarySyncChangeTokenStore.Namespace? {
        guard let containerIdentifier else { return nil }
        cloudLibrarySyncLogger.debug(
            "Resolved the iCloud sync change-token namespace for account \(accountRecordID.recordName, privacy: .private)."
        )
        return .init(
            containerIdentifier: containerIdentifier,
            accountIdentifier: accountRecordID.recordName
        )
    }

    /// Resolves the current iCloud account and builds its change-token namespace.
    ///
    /// - Returns: A namespace for the active container/account pair, or `nil`
    ///   when the client has no container.
    public func changeTokenNamespace() async throws -> CloudLibrarySyncChangeTokenStore.Namespace? {
        guard let container else { return nil }
        let accountRecordID = try await container.userRecordID()
        return changeTokenNamespace(accountRecordID: accountRecordID)
    }

    /// Encodes a sync snapshot as a CloudKit record.
    ///
    /// The snapshot identity is validated against the entry type, TMDb ID,
    /// parent series ID, and season number before a record is produced.
    ///
    /// - Throws: `CloudLibrarySyncDecodeError.invalidIdentityCombination` when
    ///   the snapshot fields do not match the derived record identity.
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
        record[Field.deletedAt] = nil
        cloudLibrarySyncLogger.debug(
            "Encoded an iCloud sync snapshot record for \(identity.rawID, privacy: .private)."
        )
        return record
    }

    /// Encodes a lean delete tombstone as a CloudKit record.
    ///
    /// Tombstones use the same record ID as the live entry and clear full snapshot
    /// fields so CloudKit does not retain stale user-state payloads after delete.
    public func record(from tombstone: LibraryEntrySyncTombstone) throws -> CKRecord {
        let identity = try Self.validatedIdentity(
            recordName: tombstone.identity.rawID,
            entryTypeValue: tombstone.entryType.cloudKitValue,
            tmdbID: tombstone.tmdbID,
            parentSeriesID: tombstone.parentSeriesID,
            seasonNumber: tombstone.seasonNumber
        )

        let record = CKRecord(recordType: Self.recordType, recordID: recordID(for: identity))
        record[Field.schemaVersion] = LibraryEntrySyncTombstone.currentSchemaVersion
        record[Field.tmdbID] = tombstone.tmdbID
        record[Field.entryType] = tombstone.entryType.cloudKitValue
        record[Field.parentSeriesID] = tombstone.parentSeriesID
        record[Field.seasonNumber] = tombstone.seasonNumber
        record[Field.deletedAt] = tombstone.deletedAt
        record[Field.onDisplay] = nil
        record[Field.dateSaved] = nil
        record[Field.watchStatus] = nil
        record[Field.dateStarted] = nil
        record[Field.dateFinished] = nil
        record[Field.isDateTrackingEnabled] = nil
        record[Field.score] = nil
        record[Field.favorite] = nil
        record[Field.notes] = nil
        record[Field.usingCustomPoster] = nil
        record[Field.customPosterURL] = nil
        record[Field.episodeProgresses] = nil
        record[Field.libraryUpdatedAt] = nil
        record[Field.trackingUpdatedAt] = nil
        cloudLibrarySyncLogger.debug(
            "Encoded an iCloud sync tombstone record for \(identity.rawID, privacy: .private)."
        )
        return record
    }

    /// Decodes and validates a CloudKit record into a sync snapshot.
    ///
    /// Throws `CloudLibrarySyncDecodeError` when the record type, schema version,
    /// required fields, enum values, identity composition, or episode progress
    /// payload are invalid.
    ///
    /// - Throws: `CloudLibrarySyncDecodeError` for invalid CloudKit records.
    public func snapshot(from record: CKRecord) throws -> LibraryEntrySyncSnapshot {
        do {
            let snapshot = try decodedSnapshot(from: record)
            cloudLibrarySyncLogger.debug(
                "Decoded an iCloud sync snapshot record for \(snapshot.identity.rawID, privacy: .private)."
            )
            return snapshot
        } catch let error as CloudLibrarySyncDecodeError {
            Self.logDecodeFailure(error, record: record)
            throw error
        }
    }

    /// Decodes a CloudKit record into either a live snapshot or lean tombstone.
    public func remoteChange(from record: CKRecord) throws -> LibraryEntrySyncRemoteChange {
        do {
            let change = try decodedRemoteChange(from: record)
            switch change {
            case .snapshot(let snapshot):
                cloudLibrarySyncLogger.debug(
                    "Decoded an iCloud sync snapshot record for \(snapshot.identity.rawID, privacy: .private)."
                )
            case .tombstone(let tombstone):
                cloudLibrarySyncLogger.debug(
                    "Decoded an iCloud sync tombstone record for \(tombstone.identity.rawID, privacy: .private)."
                )
            }
            return change
        } catch let error as CloudLibrarySyncDecodeError {
            Self.logDecodeFailure(error, record: record)
            throw error
        }
    }

    /// Performs the record-to-change decode without logging side effects.
    private func decodedRemoteChange(from record: CKRecord) throws -> LibraryEntrySyncRemoteChange {
        guard record.recordType == Self.recordType else {
            throw CloudLibrarySyncDecodeError.wrongRecordType(actual: record.recordType)
        }

        let schemaVersion: Int = try Self.requiredValue(for: Field.schemaVersion, in: record)
        let maximumSupportedSchemaVersion = max(
            LibraryEntrySyncSnapshot.currentSchemaVersion,
            LibraryEntrySyncTombstone.currentSchemaVersion
        )
        guard schemaVersion <= maximumSupportedSchemaVersion else {
            throw CloudLibrarySyncDecodeError.unsupportedSchemaVersion(schemaVersion)
        }

        if let deletedAt: Date = try Self.optionalValue(for: Field.deletedAt, in: record) {
            return .tombstone(
                try decodedTombstone(
                    from: record,
                    schemaVersion: schemaVersion,
                    deletedAt: deletedAt
                ))
        }

        return .snapshot(try decodedSnapshot(from: record))
    }

    /// Performs the strict record-to-snapshot decode without logging side effects.
    ///
    /// Keeping the decode pure lets the public wrapper centralize diagnostic
    /// logging while tests can still exercise each validation failure.
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
            trackingUpdatedAt: trackingUpdatedAt
        )
    }

    /// Decodes the lean tombstone fields from a CloudKit record.
    private func decodedTombstone(
        from record: CKRecord,
        schemaVersion: Int,
        deletedAt: Date
    ) throws -> LibraryEntrySyncTombstone {
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

        return LibraryEntrySyncTombstone(
            schemaVersion: schemaVersion,
            identity: identity,
            tmdbID: tmdbID,
            parentSeriesID: parentSeriesID,
            seasonNumber: seasonNumber,
            entryType: entryType,
            deletedAt: deletedAt
        )
    }

    /// Logs decode failures with public schema context and private identities.
    private static func logDecodeFailure(_ error: CloudLibrarySyncDecodeError, record: CKRecord) {
        switch error {
        case .wrongRecordType(let actual):
            cloudLibrarySyncLogger.error(
                "Failed to decode an iCloud sync record because the record type was \(actual, privacy: .public) instead of \(Self.recordType, privacy: .public)."
            )
        case .unsupportedSchemaVersion(let schemaVersion):
            cloudLibrarySyncLogger.error(
                "Failed to decode iCloud sync record \(record.recordType, privacy: .public) because schema version \(schemaVersion, privacy: .public) is unsupported."
            )
        case .missingRequiredField(let field):
            cloudLibrarySyncLogger.error(
                "Failed to decode iCloud sync record \(record.recordType, privacy: .public) because \(field, privacy: .public) was missing."
            )
        case .invalidScalarValue(let field):
            cloudLibrarySyncLogger.error(
                "Failed to decode iCloud sync record \(record.recordType, privacy: .public) because \(field, privacy: .public) had an invalid value."
            )
        case .invalidEnumValue(let field):
            cloudLibrarySyncLogger.error(
                "Failed to decode iCloud sync record \(record.recordType, privacy: .public) because \(field, privacy: .public) had an unknown enum value."
            )
        case .invalidIdentityCombination(let recordName):
            cloudLibrarySyncLogger.error(
                "Failed to decode iCloud sync record \(record.recordType, privacy: .public) because record identity \(recordName, privacy: .private) was invalid."
            )
        case .corruptEpisodeProgressPayload:
            cloudLibrarySyncLogger.error(
                "Failed to decode iCloud sync record \(record.recordType, privacy: .public) because the \(Field.episodeProgresses, privacy: .public) payload was corrupt."
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

    /// Reads a required CloudKit field and distinguishes missing from mistyped values.
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

    /// Reconstructs the AniShelf entry type from the CloudKit kind fields.
    ///
    /// Movies and series must not carry season context, while season records
    /// must carry both parent series and season number. The `recordName` is only
    /// used for precise decode errors.
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

    /// Derives the sync identity and verifies it exactly matches the record name.
    ///
    /// This prevents mismatched CloudKit records from applying a season payload
    /// to a movie/series identity or to the wrong TMDb entry.
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

    /// Decodes the optional custom poster string into a URL.
    fileprivate static func customPosterURL(from record: CKRecord) throws -> URL? {
        guard let value = record[Field.customPosterURL] else { return nil }
        guard let rawURL = value as? String, let url = URL(string: rawURL) else {
            throw CloudLibrarySyncDecodeError.invalidScalarValue(field: Field.customPosterURL)
        }
        return url
    }

    /// Encodes episode progress as deterministic JSON inside one CloudKit field.
    fileprivate static func encodeEpisodeProgresses(
        _ progresses: [LibraryEntrySyncSnapshot.EpisodeProgress]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(progresses)
    }

    /// Decodes the JSON episode progress payload stored in CloudKit.
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
