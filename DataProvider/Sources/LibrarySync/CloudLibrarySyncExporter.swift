//
//  CloudLibrarySyncExporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import os

fileprivate let cloudLibrarySyncExportLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.Export"
)

/// Result of pushing queued local changes to CloudKit.
public struct CloudLibrarySyncExportResult {
    public var exportedIdentities: Set<LibraryEntrySyncIdentity>

    /// Creates the export result from the identities CloudKit accepted.
    public init(exportedIdentities: Set<LibraryEntrySyncIdentity>) {
        self.exportedIdentities = exportedIdentities
    }
}

/// Builds CloudKit records from local dirty-queue entries and submits them.
public struct CloudLibrarySyncExporter: @unchecked Sendable {
    private let client: CloudLibrarySyncClient
    private let database: CloudLibrarySyncDatabase

    /// Creates an exporter for a client/database pair.
    public init(
        client: CloudLibrarySyncClient,
        database: CloudLibrarySyncDatabase
    ) {
        self.client = client
        self.database = database
    }

    /// Exports the current dirty queue.
    ///
    /// - Parameters:
    ///   - entries: Coalesced dirty-queue entries to attempt to save.
    ///   - localSnapshotsByIdentity: Current local snapshots used to materialize
    ///     upsert records. Delete entries use their tombstone snapshot directly.
    /// - Returns: The subset of identities CloudKit reported as saved.
    /// - Throws: Encoding or CloudKit errors that prevent the export attempt.
    public func export(
        entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) async throws -> CloudLibrarySyncExportResult {
        cloudLibrarySyncExportLogger.debug(
            "operation=export state=start selectedDirtyEntryCount=\(entries.count, privacy: .public) localSnapshotCount=\(localSnapshotsByIdentity.count, privacy: .public)"
        )
        let preparedRecords = try prepareRecords(
            for: entries,
            localSnapshotsByIdentity: localSnapshotsByIdentity
        )
        cloudLibrarySyncExportLogger.debug(
            "operation=export phase=prepareRecords upsertRecordCount=\(preparedRecords.upsertRecordCount, privacy: .public) tombstoneRecordCount=\(preparedRecords.tombstoneRecordCount, privacy: .public) skippedMissingLocalSnapshotCount=\(preparedRecords.skippedMissingLocalSnapshotCount, privacy: .public) preparedRecordCount=\(preparedRecords.recordsByIdentity.count, privacy: .public)"
        )
        let savedRecordIDs: [CKRecord.ID]
        do {
            savedRecordIDs = try await database.save(records: Array(preparedRecords.recordsByIdentity.values))
        } catch {
            cloudLibrarySyncExportLogger.error(
                "operation=export state=end result=failure selectedDirtyEntryCount=\(entries.count, privacy: .public) preparedRecordCount=\(preparedRecords.recordsByIdentity.count, privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
        let exportedIdentities = Set(
            savedRecordIDs.compactMap { recordID in
                preparedRecords.recordsByIdentity.first { $0.value.recordID == recordID }?.key
            })
        let partialFailureCount = max(0, preparedRecords.recordsByIdentity.count - savedRecordIDs.count)
        if partialFailureCount > 0 {
            cloudLibrarySyncExportLogger.warning(
                "operation=export state=end result=partialFailure selectedDirtyEntryCount=\(entries.count, privacy: .public) preparedRecordCount=\(preparedRecords.recordsByIdentity.count, privacy: .public) savedRecordCount=\(savedRecordIDs.count, privacy: .public) partialFailureCount=\(partialFailureCount, privacy: .public)"
            )
        } else {
            cloudLibrarySyncExportLogger.debug(
                "operation=export state=end result=success selectedDirtyEntryCount=\(entries.count, privacy: .public) preparedRecordCount=\(preparedRecords.recordsByIdentity.count, privacy: .public) savedRecordCount=\(savedRecordIDs.count, privacy: .public)"
            )
        }
        return .init(exportedIdentities: exportedIdentities)
    }

    private struct PreparedRecords {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord]
        var skippedMissingLocalSnapshotCount: Int
        var upsertRecordCount: Int
        var tombstoneRecordCount: Int
    }

    /// Converts dirty entries into CloudKit records, skipping upserts whose
    /// local snapshots no longer exist.
    private func prepareRecords(
        for entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) throws -> PreparedRecords {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord] = [:]
        var skippedMissingLocalSnapshotCount = 0
        var upsertRecordCount = 0
        var tombstoneRecordCount = 0

        for entry in entries {
            switch entry {
            case .upsert(let pendingUpsert):
                guard let snapshot = localSnapshotsByIdentity[pendingUpsert.identity] else {
                    skippedMissingLocalSnapshotCount += 1
                    continue
                }
                upsertRecordCount += 1
                recordsByIdentity[pendingUpsert.identity] = try client.record(from: snapshot)
            case .delete(let pendingDelete):
                tombstoneRecordCount += 1
                let snapshot = pendingDelete.tombstone.syncSnapshot()
                recordsByIdentity[pendingDelete.identity] = try client.record(from: snapshot)
            }
        }

        return .init(
            recordsByIdentity: recordsByIdentity,
            skippedMissingLocalSnapshotCount: skippedMissingLocalSnapshotCount,
            upsertRecordCount: upsertRecordCount,
            tombstoneRecordCount: tombstoneRecordCount
        )
    }
}
