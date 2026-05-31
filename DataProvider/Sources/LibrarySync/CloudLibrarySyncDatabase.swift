//
//  CloudLibrarySyncDatabase.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import os

fileprivate let cloudLibrarySyncDatabaseLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.CloudKit"
)

/// One CloudKit zone-change page normalized for the library sync pipeline.
public struct CloudLibrarySyncZoneChangeBatch {
    public var modifiedRecordsByID: [CKRecord.ID: CKRecord]
    public var deletedRecordIDs: [CKRecord.ID]
    public var changeToken: CKServerChangeToken
    public var moreComing: Bool

    /// Creates a normalized change batch.
    ///
    /// - Parameters:
    ///   - modifiedRecordsByID: Records created or modified in CloudKit, keyed
    ///     by record ID.
    ///   - deletedRecordIDs: Raw CloudKit deletes observed in the zone.
    ///     AniShelf normally syncs deletes as tombstone records, so callers keep
    ///     this list for diagnostics and token advancement rather than applying
    ///     it directly.
    ///   - changeToken: Server token to persist after the batch is applied.
    ///   - moreComing: Whether CloudKit has additional pages after this batch.
    public init(
        modifiedRecordsByID: [CKRecord.ID: CKRecord],
        deletedRecordIDs: [CKRecord.ID],
        changeToken: CKServerChangeToken,
        moreComing: Bool
    ) {
        self.modifiedRecordsByID = modifiedRecordsByID
        self.deletedRecordIDs = deletedRecordIDs
        self.changeToken = changeToken
        self.moreComing = moreComing
    }
}

/// Minimal CloudKit database surface used by library sync.
///
/// The protocol keeps importer/exporter logic testable while the live
/// implementation owns CloudKit-specific operation calls and partial-failure
/// handling.
public protocol CloudLibrarySyncDatabase: Sendable {
    /// Ensures the custom record zone and silent push subscription exist.
    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws

    /// Fetches one page of zone changes after an optional previous token.
    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch

    /// Saves records and returns only the record IDs CloudKit accepted.
    func save(records: [CKRecord]) async throws -> [CKRecord.ID]
}

/// Live `CloudLibrarySyncDatabase` backed by a `CKDatabase`.
public final class CloudLibrarySyncLiveDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private let database: CKDatabase

    /// Creates a live database adapter.
    ///
    /// - Parameter database: CloudKit private database for the configured
    ///   container.
    public init(database: CKDatabase) {
        self.database = database
    }

    /// Creates or reuses AniShelf's library zone and background subscription.
    ///
    /// The method treats CloudKit's common already-exists responses as success
    /// so repeated sync attempts remain idempotent.
    public func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        cloudLibrarySyncDatabaseLogger.debug(
            "operation=ensureZoneAndSubscription state=start zoneName=\(zoneID.zoneName, privacy: .public) subscriptionID=\(subscriptionID, privacy: .public)"
        )
        do {
            try await ensureZone(zoneID)
            try await ensureSubscription(subscriptionID, zoneID: zoneID)
            cloudLibrarySyncDatabaseLogger.debug(
                "operation=ensureZoneAndSubscription state=end result=success zoneName=\(zoneID.zoneName, privacy: .public) subscriptionID=\(subscriptionID, privacy: .public)"
            )
        } catch {
            cloudLibrarySyncDatabaseLogger.error(
                "operation=ensureZoneAndSubscription state=end result=failure zoneName=\(zoneID.zoneName, privacy: .public) subscriptionID=\(subscriptionID, privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
    }

    /// Fetches a single page of changes for a record zone.
    ///
    /// - Parameters:
    ///   - zoneID: Custom library zone to read.
    ///   - changeToken: Previously committed server token, or `nil` for an
    ///     initial fetch.
    /// - Returns: Modified records, raw CloudKit deletes, the next token, and
    ///   CloudKit's pagination flag.
    /// - Throws: CloudKit errors from the underlying zone-change request.
    public func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        cloudLibrarySyncDatabaseLogger.debug(
            "operation=fetchRecordZoneChanges state=start zoneName=\(zoneID.zoneName, privacy: .public) tokenState=\(changeToken == nil ? "nil" : "present", privacy: .public)"
        )

        do {
            let result = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken
            )

            var modifiedRecordsByID: [CKRecord.ID: CKRecord] = [:]
            for (recordID, modificationResult) in result.modificationResultsByID {
                let modification = try modificationResult.get()
                modifiedRecordsByID[recordID] = modification.record
            }

            cloudLibrarySyncDatabaseLogger.debug(
                "operation=fetchRecordZoneChanges state=end result=success zoneName=\(zoneID.zoneName, privacy: .public) modifiedCount=\(modifiedRecordsByID.count, privacy: .public) deletedCount=\(result.deletions.count, privacy: .public) moreComing=\(result.moreComing, privacy: .public)"
            )

            return .init(
                modifiedRecordsByID: modifiedRecordsByID,
                deletedRecordIDs: result.deletions.map(\.recordID),
                changeToken: result.changeToken,
                moreComing: result.moreComing
            )
        } catch {
            cloudLibrarySyncDatabaseLogger.error(
                "operation=fetchRecordZoneChanges state=end result=failure zoneName=\(zoneID.zoneName, privacy: .public) tokenState=\(changeToken == nil ? "nil" : "present", privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
    }

    /// Saves records non-atomically and reports the subset that succeeded.
    ///
    /// Partial CloudKit failures are converted into a successful return value
    /// containing only accepted record IDs. Non-partial failures are rethrown.
    ///
    /// - Throws: Non-partial CloudKit errors from the modify-records request.
    public func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        guard !records.isEmpty else { return [] }
        cloudLibrarySyncDatabaseLogger.debug(
            "operation=saveRecords state=start requestedCount=\(records.count, privacy: .public)"
        )

        do {
            let result = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            var savedRecordIDs: [CKRecord.ID] = []
            for (recordID, saveResult) in result.saveResults {
                if case .success = saveResult {
                    savedRecordIDs.append(recordID)
                }
            }
            cloudLibrarySyncDatabaseLogger.debug(
                "operation=saveRecords state=end result=success requestedCount=\(records.count, privacy: .public) savedCount=\(savedRecordIDs.count, privacy: .public)"
            )
            return savedRecordIDs
        } catch {
            guard
                let ckError = error as? CKError,
                ckError.code == .partialFailure,
                let partialErrors = ckError.partialErrorsByItemID
            else {
                cloudLibrarySyncDatabaseLogger.error(
                    "operation=saveRecords state=end result=failure requestedCount=\(records.count, privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
                )
                throw error
            }

            let failedIDs = Set(partialErrors.keys.compactMap { $0 as? CKRecord.ID })
            let savedRecordIDs = records.map(\.recordID).filter { !failedIDs.contains($0) }
            cloudLibrarySyncDatabaseLogger.warning(
                "operation=saveRecords state=end result=partialFailure requestedCount=\(records.count, privacy: .public) savedCount=\(savedRecordIDs.count, privacy: .public) failedCount=\(failedIDs.count, privacy: .public)"
            )
            return savedRecordIDs
        }
    }

    /// Creates the custom zone when CloudKit reports it as missing.
    private func ensureZone(_ zoneID: CKRecordZone.ID) async throws {
        let results = try await database.recordZones(for: [zoneID])
        switch results[zoneID] {
        case .success:
            return
        case .failure(let error) where error.isCloudLibrarySyncMissingItem:
            let saveResults = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)],
                deleting: []
            )
            if case .failure(let error)? = saveResults.saveResults[zoneID], !error.isCloudLibrarySyncAlreadyExists {
                throw error
            }
        case .failure(let error)?:
            throw error
        case nil:
            let saveResults = try await database.modifyRecordZones(
                saving: [CKRecordZone(zoneID: zoneID)],
                deleting: []
            )
            if case .failure(let error)? = saveResults.saveResults[zoneID], !error.isCloudLibrarySyncAlreadyExists {
                throw error
            }
        }
    }

    /// Creates the silent push subscription when CloudKit reports it as missing.
    private func ensureSubscription(
        _ subscriptionID: CKSubscription.ID,
        zoneID: CKRecordZone.ID
    ) async throws {
        let results = try await database.subscriptions(for: [subscriptionID])
        switch results[subscriptionID] {
        case .success:
            return
        case .failure(let error) where error.isCloudLibrarySyncMissingItem:
            try await saveSubscription(subscriptionID, zoneID: zoneID)
        case .failure(let error)?:
            throw error
        case nil:
            try await saveSubscription(subscriptionID, zoneID: zoneID)
        }
    }

    /// Saves a zone subscription and tolerates already-existing responses.
    private func saveSubscription(
        _ subscriptionID: CKSubscription.ID,
        zoneID: CKRecordZone.ID
    ) async throws {
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let saveResults = try await database.modifySubscriptions(
            saving: [subscription],
            deleting: []
        )
        if case .failure(let error)? = saveResults.saveResults[subscriptionID],
            !error.isCloudLibrarySyncAlreadyExists
        {
            throw error
        }
    }
}

extension Error {
    fileprivate var isCloudLibrarySyncMissingItem: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.code == .unknownItem || ckError.code == .zoneNotFound
    }

    fileprivate var isCloudLibrarySyncAlreadyExists: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.code == .serverRejectedRequest || ckError.code == .constraintViolation
    }
}
