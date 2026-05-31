//
//  CloudLibrarySyncImporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation

public struct CloudLibrarySyncImportBatch {
    public var snapshots: [LibraryEntrySyncSnapshot]
    public var remoteSnapshots: [LibraryEntrySyncSnapshot]
    public var ignoredDeletedRecordIDs: [CKRecord.ID]
    public var changeToken: CKServerChangeToken
    public var namespace: CloudLibrarySyncChangeTokenStore.Namespace
    public var zoneID: CKRecordZone.ID

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

public struct CloudLibrarySyncImporter: @unchecked Sendable {
    private let client: CloudLibrarySyncClient
    private let database: CloudLibrarySyncDatabase
    private let changeTokenStore: CloudLibrarySyncChangeTokenStore

    public init(
        client: CloudLibrarySyncClient,
        database: CloudLibrarySyncDatabase,
        changeTokenStore: CloudLibrarySyncChangeTokenStore = .init()
    ) {
        self.client = client
        self.database = database
        self.changeTokenStore = changeTokenStore
    }

    public func prepareRemoteSync() async throws {
        try await database.ensureZoneAndSubscription(
            zoneID: Self.zoneID,
            subscriptionID: CloudLibrarySyncClient.subscriptionID
        )
    }

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

            changeTokenStore.removeToken(for: Self.zoneID, namespace: namespace)
            return try await fetchChanges(
                namespace: namespace,
                localSnapshotsByIdentity: localSnapshotsByIdentity,
                startingToken: nil
            )
        }
    }

    public func commit(_ batch: CloudLibrarySyncImportBatch) {
        changeTokenStore.setToken(batch.changeToken, for: batch.zoneID, namespace: batch.namespace)
    }

    private func fetchChanges(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        startingToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncImportBatch {
        var currentToken = startingToken
        var finalToken: CKServerChangeToken?
        var remoteSnapshotsByID: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot] = [:]
        var ignoredDeletedRecordIDs: [CKRecord.ID] = []

        repeat {
            let batch = try await database.fetchRecordZoneChanges(
                in: Self.zoneID,
                since: currentToken
            )
            for record in batch.modifiedRecordsByID.values {
                let snapshot = try client.snapshot(from: record)
                if let existing = remoteSnapshotsByID[snapshot.identity] {
                    remoteSnapshotsByID[snapshot.identity] = try existing.merged(with: snapshot)
                } else {
                    remoteSnapshotsByID[snapshot.identity] = snapshot
                }
            }
            ignoredDeletedRecordIDs.append(contentsOf: batch.deletedRecordIDs)
            currentToken = batch.changeToken
            finalToken = batch.changeToken

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
