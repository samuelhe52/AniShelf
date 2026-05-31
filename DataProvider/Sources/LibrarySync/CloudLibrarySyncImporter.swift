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
    public var snapshots: [LibraryEntrySyncSnapshot]
    public var remoteSnapshots: [LibraryEntrySyncSnapshot]
    public var ignoredDeletedRecordIDs: [CKRecord.ID]
    public var changeToken: CKServerChangeToken
    public var namespace: CloudLibrarySyncChangeTokenStore.Namespace
    public var zoneID: CKRecordZone.ID

    /// Creates an import batch ready for application to the local store.
    ///
    /// - Parameters:
    ///   - snapshots: Remote snapshots after merging with local snapshots for
    ///     the same identity.
    ///   - remoteSnapshots: Decoded remote snapshots before local conflict
    ///     merging. The coordinator uses this to reconcile dirty-queue entries.
    ///   - ignoredDeletedRecordIDs: Raw CloudKit record deletions. AniShelf
    ///     applies tombstone records instead of raw deletes, so these are kept
    ///     for logging and diagnostics.
    ///   - changeToken: Server change token to commit after local application
    ///     succeeds.
    ///   - namespace: Container/account namespace for the token.
    ///   - zoneID: CloudKit zone that produced the token.
    public init(
        snapshots: [LibraryEntrySyncSnapshot],
        remoteSnapshots: [LibraryEntrySyncSnapshot],
        ignoredDeletedRecordIDs: [CKRecord.ID],
        changeToken: CKServerChangeToken,
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        zoneID: CKRecordZone.ID
    ) {
        self.snapshots = snapshots
        self.remoteSnapshots = remoteSnapshots
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
        cloudLibrarySyncImportLogger.debug(
            "operation=prepareRemoteSync state=start"
        )
        do {
            try await database.ensureZoneAndSubscription(
                zoneID: Self.zoneID,
                subscriptionID: CloudLibrarySyncClient.subscriptionID
            )
            cloudLibrarySyncImportLogger.debug(
                "operation=prepareRemoteSync state=end result=success"
            )
        } catch {
            cloudLibrarySyncImportLogger.error(
                "operation=prepareRemoteSync state=end result=failure errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
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
        cloudLibrarySyncImportLogger.debug(
            "operation=fetchChanges state=start tokenState=\(token == nil ? "nil" : "present", privacy: .public) localSnapshotCount=\(localSnapshotsByIdentity.count, privacy: .public)"
        )
        do {
            return try await fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshotsByIdentity,
                startingToken: token
            )
        } catch {
            guard error.isCloudLibrarySyncChangeTokenExpired, token != nil else {
                cloudLibrarySyncImportLogger.error(
                    "operation=fetchChanges state=end result=failure tokenState=\(token == nil ? "nil" : "present", privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
                )
                throw error
            }

            cloudLibrarySyncImportLogger.warning(
                "operation=fetchChanges tokenState=expired action=reset"
            )
            changeTokenStore.removeToken(for: Self.zoneID, namespace: namespace)
            do {
                return try await fetchChanges(
                    namespace: namespace,
                    localSnapshotsByIdentity: localSnapshotsByIdentity,
                    startingToken: nil
                )
            } catch {
                cloudLibrarySyncImportLogger.error(
                    "operation=fetchChanges state=end result=failure tokenState=nil retryAfterExpiredToken=true errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
                )
                throw error
            }
        }
    }

    /// Persists the server change token for a successfully applied batch.
    public func commit(_ batch: CloudLibrarySyncImportBatch) {
        changeTokenStore.setToken(batch.changeToken, for: batch.zoneID, namespace: batch.namespace)
        cloudLibrarySyncImportLogger.debug(
            "operation=commitToken result=success snapshotCount=\(batch.snapshots.count, privacy: .public) remoteSnapshotCount=\(batch.remoteSnapshots.count, privacy: .public)"
        )
    }

    /// Fetches all CloudKit pages for the zone starting at a specific token.
    ///
    /// Modified records are coalesced by sync identity before they are merged
    /// with local snapshots. Raw CloudKit deletes are intentionally not applied
    /// as library deletes because AniShelf's sync deletion semantics flow
    /// through explicit tombstone records.
    private func fetchChanges(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        startingToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncImportBatch {
        var currentToken = startingToken
        var finalToken: CKServerChangeToken?
        var remoteSnapshotsByID: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot] = [:]
        var ignoredDeletedRecordIDs: [CKRecord.ID] = []
        var batchCount = 0
        var decodedSnapshotCount = 0
        var modifiedRecordCount = 0
        var rawDeletedRecordCount = 0

        repeat {
            batchCount += 1
            let batch = try await database.fetchRecordZoneChanges(
                in: Self.zoneID,
                since: currentToken
            )
            modifiedRecordCount += batch.modifiedRecordsByID.count
            rawDeletedRecordCount += batch.deletedRecordIDs.count
            for record in batch.modifiedRecordsByID.values {
                let snapshot = try client.snapshot(from: record)
                decodedSnapshotCount += 1
                if let existing = remoteSnapshotsByID[snapshot.identity] {
                    remoteSnapshotsByID[snapshot.identity] = try existing.merged(with: snapshot)
                } else {
                    remoteSnapshotsByID[snapshot.identity] = snapshot
                }
            }
            ignoredDeletedRecordIDs.append(contentsOf: batch.deletedRecordIDs)
            currentToken = batch.changeToken
            finalToken = batch.changeToken

            cloudLibrarySyncImportLogger.debug(
                "operation=fetchChanges batchIndex=\(batchCount, privacy: .public) modifiedRecordCount=\(batch.modifiedRecordsByID.count, privacy: .public) rawDeletedRecordCount=\(batch.deletedRecordIDs.count, privacy: .public) decodedSnapshotCount=\(decodedSnapshotCount, privacy: .public) coalescedIdentityCount=\(remoteSnapshotsByID.count, privacy: .public) moreComing=\(batch.moreComing, privacy: .public)"
            )

            if !batch.moreComing {
                break
            }
        } while true

        let remoteSnapshots = remoteSnapshotsByID.values.sorted { $0.identity.rawID < $1.identity.rawID }
        let resolvedSnapshots = try remoteSnapshots.map { remoteSnapshot in
            guard let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity] else {
                return remoteSnapshot
            }
            return try localSnapshot.merged(with: remoteSnapshot)
        }

        guard let finalToken else {
            throw CloudLibrarySyncImportError.missingChangeToken
        }

        cloudLibrarySyncImportLogger.debug(
            "operation=fetchChanges state=end result=success batchCount=\(batchCount, privacy: .public) modifiedRecordCount=\(modifiedRecordCount, privacy: .public) rawDeletedRecordCount=\(rawDeletedRecordCount, privacy: .public) decodedSnapshotCount=\(decodedSnapshotCount, privacy: .public) coalescedIdentityCount=\(remoteSnapshots.count, privacy: .public) resolvedSnapshotCount=\(resolvedSnapshots.count, privacy: .public) pendingTokenReceived=true"
        )

        return .init(
            snapshots: resolvedSnapshots,
            remoteSnapshots: remoteSnapshots,
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
