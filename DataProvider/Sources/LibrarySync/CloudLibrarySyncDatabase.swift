//
//  CloudLibrarySyncDatabase.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation

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

    /// Fetches quarantined records directly for a later app version to retry decoding.
    /// Missing records are omitted from the result.
    func fetchRecords(ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord]

    /// Saves records and returns only the record IDs CloudKit accepted.
    func save(records: [CKRecord]) async throws -> [CKRecord.ID]
}

/// Live `CloudLibrarySyncDatabase` backed by a `CKDatabase`.
public final class CloudLibrarySyncLiveDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    static let recordZoneChangeResultsLimit = 350

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
        try await ensureZone(zoneID)
        try await ensureSubscription(subscriptionID, zoneID: zoneID)
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
        let result = try await database.recordZoneChanges(
            inZoneWith: zoneID,
            since: changeToken,
            resultsLimit: Self.recordZoneChangeResultsLimit
        )

        var modifiedRecordsByID: [CKRecord.ID: CKRecord] = [:]
        for (recordID, modificationResult) in result.modificationResultsByID {
            let modification = try modificationResult.get()
            modifiedRecordsByID[recordID] = modification.record
        }

        return .init(
            modifiedRecordsByID: modifiedRecordsByID,
            deletedRecordIDs: result.deletions.map(\.recordID),
            changeToken: result.changeToken,
            moreComing: result.moreComing
        )
    }

    public func fetchRecords(ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        guard !ids.isEmpty else { return [:] }
        var records: [CKRecord.ID: CKRecord] = [:]
        for start in stride(from: 0, to: ids.count, by: Self.recordZoneChangeResultsLimit) {
            let end = min(start + Self.recordZoneChangeResultsLimit, ids.count)
            let results = try await database.records(for: Array(ids[start..<end]))
            for (recordID, result) in results {
                switch result {
                case .success(let record):
                    records[recordID] = record
                case .failure(let error) where error.isCloudLibrarySyncMissingItem:
                    continue
                case .failure(let error):
                    throw error
                }
            }
        }
        return records
    }

    /// Saves records non-atomically and preserves both accepted IDs and
    /// per-record failures so the caller can retry the remaining work.
    public func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        guard !records.isEmpty else { return [] }
        do {
            let result = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            var savedRecordIDs: [CKRecord.ID] = []
            var failedErrorsByID: [CKRecord.ID: any Error] = [:]
            for (recordID, saveResult) in result.saveResults {
                switch saveResult {
                case .success:
                    savedRecordIDs.append(recordID)
                case .failure(let error):
                    failedErrorsByID[recordID] = error
                }
            }
            for record in records where result.saveResults[record.recordID] == nil {
                failedErrorsByID[record.recordID] = CloudLibrarySyncSaveResultError.missingResult
            }
            if !failedErrorsByID.isEmpty {
                throw CloudLibrarySyncPartialSaveFailure(
                    savedRecordIDs: savedRecordIDs,
                    failedErrorsByID: failedErrorsByID
                )
            }
            return savedRecordIDs
        } catch {
            if error is CloudLibrarySyncPartialSaveFailure { throw error }
            guard
                let ckError = error as? CKError,
                ckError.code == .partialFailure,
                let partialErrors = ckError.partialErrorsByItemID
            else {
                throw error
            }

            let failures = partialErrors.reduce(into: [CKRecord.ID: any Error]()) { result, item in
                if let recordID = item.key as? CKRecord.ID {
                    result[recordID] = item.value
                }
            }
            guard !failures.isEmpty else { throw ckError }
            throw CloudLibrarySyncPartialSaveFailure(
                // An aggregate error supplies failures but no per-record success
                // confirmations. Retrying an accepted record is safer than
                // dropping an unconfirmed record from the local queue.
                savedRecordIDs: [],
                failedErrorsByID: failures,
                aggregateError: ckError
            )
        }
    }

    /// Creates the custom zone when CloudKit reports it as missing.
    private func ensureZone(_ zoneID: CKRecordZone.ID) async throws {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
        let pending = CloudLibrarySyncOperation(operation)
        operation.perRecordZoneResultBlock = { [weak pending] _, result in
            pending?.finish(result.map { _ in () })
        }
        operation.fetchRecordZonesResultBlock = { [weak pending] result in
            // A successful lookup must have supplied a per-zone result.
            pending?.finish(result.flatMap { .failure(CKError(.unknownItem)) })
        }
        do {
            try await pending.run { self.database.add(operation) }
        } catch  where error.isCloudLibrarySyncMissingItem {
            try Task.checkCancellation()
            let save = CKModifyRecordZonesOperation(
                recordZonesToSave: [CKRecordZone(zoneID: zoneID)], recordZoneIDsToDelete: nil
            )
            let pendingSave = CloudLibrarySyncOperation(save)
            save.perRecordZoneSaveBlock = { [weak pendingSave] _, result in
                pendingSave?.finish(result.map { _ in () })
            }
            save.modifyRecordZonesResultBlock = { [weak pendingSave] result in
                pendingSave?.finish(result)
            }
            do {
                try await pendingSave.run { self.database.add(save) }
            } catch  where error.isCloudLibrarySyncAlreadyExists {
                return
            }
        }
    }

    /// Creates the silent push subscription when CloudKit reports it as missing.
    private func ensureSubscription(
        _ subscriptionID: CKSubscription.ID,
        zoneID: CKRecordZone.ID
    ) async throws {
        try Task.checkCancellation()
        let operation = CKFetchSubscriptionsOperation(subscriptionIDs: [subscriptionID])
        let pending = CloudLibrarySyncOperation(operation)
        operation.perSubscriptionResultBlock = { [weak pending] _, result in
            pending?.finish(result.map { _ in () })
        }
        operation.fetchSubscriptionsResultBlock = { [weak pending] result in
            pending?.finish(result.flatMap { .failure(CKError(.unknownItem)) })
        }
        do {
            try await pending.run { self.database.add(operation) }
        } catch  where error.isCloudLibrarySyncMissingItem {
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

        try Task.checkCancellation()
        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil
        )
        let pending = CloudLibrarySyncOperation(operation)
        operation.perSubscriptionSaveBlock = { [weak pending] _, result in
            pending?.finish(result.map { _ in () })
        }
        operation.modifySubscriptionsResultBlock = { [weak pending] result in
            pending?.finish(result)
        }
        do {
            try await pending.run { self.database.add(operation) }
        } catch  where error.isCloudLibrarySyncAlreadyExists {
            return
        }
    }
}

fileprivate enum CloudLibrarySyncSaveResultError: LocalizedError {
    case missingResult

    var errorDescription: String? {
        "CloudKit did not confirm whether a library sync record was saved."
    }
}

/// Accepted records from a non-atomic save remain confirmed while failed
/// records retain CloudKit's retry and quota information.
public struct CloudLibrarySyncPartialSaveFailure: Error, LocalizedError {
    public let savedRecordIDs: [CKRecord.ID]
    public let failedErrorsByID: [CKRecord.ID: any Error]
    public let aggregateError: CKError?

    public init(
        savedRecordIDs: [CKRecord.ID],
        failedErrorsByID: [CKRecord.ID: any Error],
        aggregateError: CKError? = nil
    ) {
        self.savedRecordIDs = savedRecordIDs
        self.failedErrorsByID = failedErrorsByID
        self.aggregateError = aggregateError
    }

    public var retryAfterSeconds: TimeInterval? {
        (failedErrorsByID.values.compactMap { ($0 as? CKError)?.retryAfterSeconds }
            + [aggregateError?.retryAfterSeconds].compactMap(\.self)).max()
    }

    public var isQuotaExceeded: Bool {
        !failedErrorsByID.isEmpty
            && failedErrorsByID.values.allSatisfy { ($0 as? CKError)?.code == .quotaExceeded }
    }

    /// An account failure affects the whole save, even if CloudKit also
    /// reports unrelated per-record errors in the same partial result.
    public var accountError: CKError? {
        let errors = failedErrorsByID.values.compactMap { $0 as? CKError }
        return errors.first { $0.code == .notAuthenticated }
            ?? errors.first { $0.code == .permissionFailure }
    }

    /// Whether every failure concerns only its own record.
    ///
    /// Those records can stay queued for a later attempt while the rest of the
    /// export finishes. Account, network, quota, and throttling errors affect
    /// every record, so they leave this `false` and fail the pass instead.
    public var isRecordScoped: Bool {
        !failedErrorsByID.isEmpty
            && failedErrorsByID.values.allSatisfy(\.isCloudLibrarySyncRecordScopedSaveError)
    }

    public var errorDescription: String? {
        failedErrorsByID.values.first?.localizedDescription
            ?? aggregateError?.localizedDescription
    }
}

extension Error {
    /// Whether CloudKit rejected one record for a reason that leaves the rest
    /// of the save unaffected, such as invalid or oversized record contents.
    var isCloudLibrarySyncRecordScopedSaveError: Bool {
        if self is CloudLibrarySyncSaveResultError { return true }
        guard let ckError = self as? CKError else { return false }
        switch ckError.code {
        case .invalidArguments, .constraintViolation, .limitExceeded, .serverRecordChanged,
            .batchRequestFailed, .referenceViolation, .assetFileNotFound, .assetFileModified:
            return true
        default:
            return false
        }
    }

    fileprivate var isCloudLibrarySyncMissingItem: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.code == .unknownItem || ckError.code == .zoneNotFound
    }

    fileprivate var isCloudLibrarySyncAlreadyExists: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.code == .serverRejectedRequest || ckError.code == .constraintViolation
    }
}
