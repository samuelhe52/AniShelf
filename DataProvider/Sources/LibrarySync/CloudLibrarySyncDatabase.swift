//
//  CloudLibrarySyncDatabase.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import os

private let cloudLibrarySyncDatabaseLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.CloudKit"
)

public struct CloudLibrarySyncZoneChangeBatch {
    public var modifiedRecordsByID: [CKRecord.ID: CKRecord]
    public var deletedRecordIDs: [CKRecord.ID]
    public var changeToken: CKServerChangeToken
    public var moreComing: Bool

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

public protocol CloudLibrarySyncDatabase: Sendable {
    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch

    func save(records: [CKRecord]) async throws -> [CKRecord.ID]
}

public final class CloudLibrarySyncLiveDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private let database: CKDatabase

    public init(database: CKDatabase) {
        self.database = database
    }

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
