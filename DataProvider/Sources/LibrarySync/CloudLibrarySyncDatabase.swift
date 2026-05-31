//
//  CloudLibrarySyncDatabase.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation

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
        try await ensureZone(zoneID)
        try await ensureSubscription(subscriptionID, zoneID: zoneID)
    }

    public func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        let result = try await database.recordZoneChanges(
            inZoneWith: zoneID,
            since: changeToken
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

    public func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        guard !records.isEmpty else { return [] }

        do {
            let result = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            return result.saveResults.compactMap { recordID, saveResult in
                guard case .success = saveResult else { return nil }
                return recordID
            }
        } catch {
            guard
                let ckError = error as? CKError,
                ckError.code == .partialFailure,
                let partialErrors = ckError.partialErrorsByItemID
            else {
                throw error
            }

            let failedIDs = Set(partialErrors.keys.compactMap { $0 as? CKRecord.ID })
            return records.map(\.recordID).filter { !failedIDs.contains($0) }
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
