//
//  CloudLibrarySyncImporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import DataProvider
import Foundation
import os

fileprivate let cloudLibrarySyncImportLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.Import"
)

/// Remote change batch after decoding and local conflict resolution.
public struct CloudLibrarySyncImportBatch {
    public var changes: [LibraryEntrySyncRemoteChange]
    public var remoteChanges: [LibraryEntrySyncRemoteChange]
    public var settingsSnapshot: LibrarySettingsSyncSnapshot?
    public var ignoredDeletedRecordIDs: [CKRecord.ID]
    public var quarantinedRecordIDs: Set<CKRecord.ID>
    public var changeToken: CKServerChangeToken
    public var namespace: CloudLibrarySyncChangeTokenStore.Namespace
    public var zoneID: CKRecordZone.ID
    var quarantineDecodedRecordIDs: Set<CKRecord.ID> = []
    var quarantineDeletedRecordIDs: Set<CKRecord.ID> = []
    var quarantineFailures: [CloudLibrarySyncQuarantineStore.Entry] = []

    /// Creates an import batch ready for application to the local store.
    ///
    /// - Parameters:
    ///   - changes: Remote changes after merging snapshots with local snapshots
    ///     for the same identity.
    ///   - remoteChanges: Decoded remote changes before local conflict merging.
    ///     Kept for diagnostics and review comparisons.
    ///   - settingsSnapshot: Latest remote settings record included in the
    ///     fetched change set, when one exists.
    ///   - ignoredDeletedRecordIDs: Raw CloudKit record deletions. AniShelf
    ///     applies tombstone records instead of raw deletes, so these are kept
    ///     for logging and diagnostics.
    ///   - quarantinedRecordIDs: Records this build must not overwrite.
    ///   - changeToken: Server change token to commit after local application
    ///     succeeds.
    ///   - namespace: Container/account namespace for the token.
    ///   - zoneID: CloudKit zone that produced the token.
    public init(
        changes: [LibraryEntrySyncRemoteChange],
        remoteChanges: [LibraryEntrySyncRemoteChange],
        settingsSnapshot: LibrarySettingsSyncSnapshot?,
        ignoredDeletedRecordIDs: [CKRecord.ID],
        quarantinedRecordIDs: Set<CKRecord.ID> = [],
        changeToken: CKServerChangeToken,
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        zoneID: CKRecordZone.ID
    ) {
        self.changes = changes
        self.remoteChanges = remoteChanges
        self.settingsSnapshot = settingsSnapshot
        self.ignoredDeletedRecordIDs = ignoredDeletedRecordIDs
        self.quarantinedRecordIDs = quarantinedRecordIDs
        self.changeToken = changeToken
        self.namespace = namespace
        self.zoneID = zoneID
    }
}

/// Fetches remote CloudKit changes and prepares them for local application.
public struct CloudLibrarySyncImporter: @unchecked Sendable {
    private let client: CloudLibrarySyncClient
    private let database: CloudLibrarySyncDatabase
    private let changeTokenStore: CloudLibrarySyncChangeTokenStore
    private let quarantineStore: CloudLibrarySyncQuarantineStore
    private let appVersion: String

    /// Creates an importer for a client/database/token-store combination.
    ///
    /// - Parameters:
    ///   - client: Encoder/decoder for the library sync record schema.
    ///   - database: Database adapter used to prepare the zone and fetch changes.
    ///   - changeTokenStore: Store for per-container/per-account zone tokens.
    ///   - quarantineStore: Durable store for undecodable records.
    ///   - appVersion: Version used to retry quarantined records after an upgrade.
    public init(
        client: CloudLibrarySyncClient,
        database: CloudLibrarySyncDatabase,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init(),
        quarantineStore: CloudLibrarySyncQuarantineStore = .init(),
        appVersion: String? = nil
    ) {
        self.client = client
        self.database = database
        self.changeTokenStore = changeTokenStore
        self.quarantineStore = quarantineStore
        self.appVersion = appVersion ?? Self.runningAppVersion
    }

    public func quarantinedRecordIDs(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace
    ) throws -> Set<CKRecord.ID> {
        Set(try quarantineStore.entries(namespace: namespace, zoneID: Self.zoneID).map(\.recordID))
    }

    /// Ensures the remote zone and silent subscription are available.
    public func prepareRemoteSync() async throws {
        try await database.ensureZoneAndSubscription(
            zoneID: Self.zoneID,
            subscriptionID: CloudLibrarySyncClient.subscriptionID
        )
    }

    /// Fetches remote changes and resolves them against the current local state.
    ///
    /// If the stored token has expired, the importer clears it and retries once
    /// from the beginning of the zone.
    ///
    /// - Parameters:
    ///   - namespace: Container/account namespace for loading the previous token.
    ///   - localSnapshotsByIdentity: Current local snapshots used to merge
    ///     incoming remote changes before application.
    /// - Returns: A batch whose token must be committed only after local
    ///   application succeeds.
    /// - Throws: CloudKit fetch errors, decode errors, merge errors, or
    ///   `CloudLibrarySyncImportError.missingChangeToken`.
    public func fetchChanges(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        localSnapshotsByIdentity: [LibraryEntryIdentity: LibraryEntrySyncSnapshot]
    ) async throws -> CloudLibrarySyncImportBatch {
        let token = changeTokenStore.token(for: Self.zoneID, namespace: namespace)
        do {
            return try await fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshotsByIdentity,
                startingToken: token
            )
        } catch {
            guard error.isCloudLibrarySyncChangeTokenExpired, token != nil else {
                throw error
            }

            cloudLibrarySyncImportLogger.warning(
                "The stored iCloud sync change token expired. Clearing it and refetching from the start of the zone."
            )
            changeTokenStore.removeToken(for: Self.zoneID, namespace: namespace)
            return try await fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshotsByIdentity,
                startingToken: nil
            )
        }
    }

    /// Fetches the complete current zone without consulting a persisted token.
    ///
    /// Bootstrap uses this path when the active account or remote scope changes,
    /// so an older token for that scope cannot turn reconciliation into an
    /// incremental fetch.
    public func fetchChangesFromBeginning(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        localSnapshotsByIdentity: [LibraryEntryIdentity: LibraryEntrySyncSnapshot]
    ) async throws -> CloudLibrarySyncImportBatch {
        try await fetchChanges(
            namespace: namespace,
            localSnapshotsByIdentity: localSnapshotsByIdentity,
            startingToken: nil
        )
    }

    /// Persists the server change token for a successfully applied batch.
    public func commit(_ batch: CloudLibrarySyncImportBatch) throws {
        _ = try quarantineStore.reconcile(
            namespace: batch.namespace,
            zoneID: batch.zoneID,
            decodedRecordIDs: batch.quarantineDecodedRecordIDs,
            deletedRecordIDs: batch.quarantineDeletedRecordIDs,
            failures: batch.quarantineFailures
        )
        changeTokenStore.setToken(batch.changeToken, for: batch.zoneID, namespace: batch.namespace)
    }

    /// Fetches all CloudKit pages for the zone starting at a specific token.
    ///
    /// Modified records are coalesced by sync identity before snapshots are
    /// merged with local snapshots. Raw CloudKit deletes are intentionally not
    /// applied as library deletes because AniShelf's sync deletion semantics
    /// flow through explicit tombstone records.
    private func fetchChanges(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        localSnapshotsByIdentity: [LibraryEntryIdentity: LibraryEntrySyncSnapshot],
        startingToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncImportBatch {
        let existingQuarantined = try quarantineStore.entries(namespace: namespace, zoneID: Self.zoneID)
        let retryRecordIDs = existingQuarantined
            .filter { $0.attemptedAppVersion != appVersion }
            .map(\.recordID)
        let retriedRecords: [CKRecord.ID: CKRecord] =
            retryRecordIDs.isEmpty
            ? [:] : try await database.fetchRecords(ids: retryRecordIDs)
        let missingRetriedRecordIDs = Set(retryRecordIDs).subtracting(retriedRecords.keys)
        var currentToken = startingToken
        var finalToken: CKServerChangeToken?
        var remoteChangesByID: [LibraryEntryIdentity: LibraryEntrySyncRemoteChange] = [:]
        var settingsSnapshot: LibrarySettingsSyncSnapshot?
        var ignoredDeletedRecordIDs: [CKRecord.ID] = []
        var decodedRecordIDs: Set<CKRecord.ID> = []
        var failedRecords: [CKRecord.ID: CloudLibrarySyncQuarantineStore.Entry] = [:]
        var remainingRetriedRecords = Array(retriedRecords.values)
        repeat {
            let batch = try await database.fetchRecordZoneChanges(
                in: Self.zoneID,
                since: currentToken
            )
            for record in remainingRetriedRecords + Array(batch.modifiedRecordsByID.values) {
                do {
                    let decodedChange = try client.zoneRecordChange(from: record)
                    failedRecords.removeValue(forKey: record.recordID)
                    decodedRecordIDs.insert(record.recordID)
                    switch decodedChange {
                    case .entry(let change):
                        if let existing = remoteChangesByID[change.identity] {
                            remoteChangesByID[change.identity] = try existing.merged(with: change)
                        } else {
                            remoteChangesByID[change.identity] = change
                        }
                    case .settings(let snapshot):
                        // Later pages carry later server versions of the single
                        // settings record, whatever the writing device's clock said.
                        settingsSnapshot = snapshot
                    }
                } catch let error as CloudLibrarySyncDecodeError {
                    decodedRecordIDs.remove(record.recordID)
                    failedRecords[record.recordID] = .init(
                        record: record,
                        namespace: namespace,
                        reason: error.localizedDescription,
                        attemptedAppVersion: appVersion
                    )
                    remoteChangesByID = remoteChangesByID.filter { $0.key.rawID != record.recordID.recordName }
                    if record.recordID == client.librarySettingsRecordID {
                        settingsSnapshot = nil
                    }
                }
            }
            remainingRetriedRecords.removeAll()
            ignoredDeletedRecordIDs.append(contentsOf: batch.deletedRecordIDs)
            for recordID in batch.deletedRecordIDs {
                failedRecords.removeValue(forKey: recordID)
                decodedRecordIDs.remove(recordID)
                remoteChangesByID = remoteChangesByID.filter { $0.key.rawID != recordID.recordName }
                if recordID == client.librarySettingsRecordID { settingsSnapshot = nil }
            }
            currentToken = batch.changeToken
            finalToken = batch.changeToken

            if !batch.moreComing {
                break
            }
        } while true

        let remoteChanges = remoteChangesByID.values.sorted { $0.identity.rawID < $1.identity.rawID }
        let resolvedChanges = try remoteChanges.map { remoteChange in
            guard case .snapshot(let remoteSnapshot) = remoteChange,
                let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity]
            else {
                return remoteChange
            }
            return .snapshot(try localSnapshot.merged(with: remoteSnapshot))
        }

        guard let finalToken else {
            throw CloudLibrarySyncImportError.missingChangeToken
        }

        let deletedRecordIDs = Set(ignoredDeletedRecordIDs).union(missingRetriedRecordIDs)
        let resolvedRecordIDs = decodedRecordIDs.union(deletedRecordIDs)
        let quarantinedRecordIDs = Set(existingQuarantined.map(\.recordID))
            .subtracting(resolvedRecordIDs)
            .union(failedRecords.keys)
        var result = CloudLibrarySyncImportBatch(
            changes: resolvedChanges,
            remoteChanges: remoteChanges,
            settingsSnapshot: settingsSnapshot,
            ignoredDeletedRecordIDs: ignoredDeletedRecordIDs,
            quarantinedRecordIDs: quarantinedRecordIDs,
            changeToken: finalToken,
            namespace: namespace,
            zoneID: Self.zoneID
        )
        result.quarantineDecodedRecordIDs = decodedRecordIDs
        result.quarantineDeletedRecordIDs = deletedRecordIDs
        result.quarantineFailures = Array(failedRecords.values)
        return result
    }

    private static var zoneID: CKRecordZone.ID {
        CloudLibrarySyncClient.recordZoneID
    }

    private static var runningAppVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return "\(version).\(build)"
    }
}

public enum CloudLibrarySyncImportError: Error, Equatable {
    case missingChangeToken
}

extension Error {
    fileprivate var isCloudLibrarySyncChangeTokenExpired: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.code == .changeTokenExpired
    }
}
