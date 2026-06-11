//
//  CloudLibrarySyncImporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
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
    public var changeToken: CKServerChangeToken
    public var namespace: CloudLibrarySyncChangeTokenStore.Namespace
    public var zoneID: CKRecordZone.ID

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
    ///   - changeToken: Server change token to commit after local application
    ///     succeeds.
    ///   - namespace: Container/account namespace for the token.
    ///   - zoneID: CloudKit zone that produced the token.
    public init(
        changes: [LibraryEntrySyncRemoteChange],
        remoteChanges: [LibraryEntrySyncRemoteChange],
        settingsSnapshot: LibrarySettingsSyncSnapshot?,
        ignoredDeletedRecordIDs: [CKRecord.ID],
        changeToken: CKServerChangeToken,
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        zoneID: CKRecordZone.ID
    ) {
        self.changes = changes
        self.remoteChanges = remoteChanges
        self.settingsSnapshot = settingsSnapshot
        self.ignoredDeletedRecordIDs = ignoredDeletedRecordIDs
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

    /// Creates an importer for a client/database/token-store combination.
    ///
    /// - Parameters:
    ///   - client: Encoder/decoder for the library sync record schema.
    ///   - database: Database adapter used to prepare the zone and fetch changes.
    ///   - changeTokenStore: Store for per-container/per-account zone tokens.
    public init(
        client: CloudLibrarySyncClient,
        database: CloudLibrarySyncDatabase,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init()
    ) {
        self.client = client
        self.database = database
        self.changeTokenStore = changeTokenStore
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
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
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

    /// Persists the server change token for a successfully applied batch.
    public func commit(_ batch: CloudLibrarySyncImportBatch) {
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
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        startingToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncImportBatch {
        var currentToken = startingToken
        var finalToken: CKServerChangeToken?
        var remoteChangesByID: [LibraryEntrySyncIdentity: LibraryEntrySyncRemoteChange] = [:]
        var settingsSnapshot: LibrarySettingsSyncSnapshot?
        var ignoredDeletedRecordIDs: [CKRecord.ID] = []
        repeat {
            let batch = try await database.fetchRecordZoneChanges(
                in: Self.zoneID,
                since: currentToken
            )
            for record in batch.modifiedRecordsByID.values {
                let decodedChange = try client.zoneRecordChange(from: record)
                switch decodedChange {
                case .entry(let change):
                    if let existing = remoteChangesByID[change.identity] {
                        remoteChangesByID[change.identity] = try existing.merged(with: change)
                    } else {
                        remoteChangesByID[change.identity] = change
                    }
                case .settings(let snapshot):
                    if let existing = settingsSnapshot {
                        settingsSnapshot = existing.updatedAt >= snapshot.updatedAt ? existing : snapshot
                    } else {
                        settingsSnapshot = snapshot
                    }
                }
            }
            ignoredDeletedRecordIDs.append(contentsOf: batch.deletedRecordIDs)
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

        return .init(
            changes: resolvedChanges,
            remoteChanges: remoteChanges,
            settingsSnapshot: settingsSnapshot,
            ignoredDeletedRecordIDs: ignoredDeletedRecordIDs,
            changeToken: finalToken,
            namespace: namespace,
            zoneID: Self.zoneID
        )
    }

    private static var zoneID: CKRecordZone.ID {
        CloudLibrarySyncClient.recordZoneID
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
