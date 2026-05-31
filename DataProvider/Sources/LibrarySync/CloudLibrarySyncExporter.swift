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
    ///     upsert records. Delete entries use lean tombstone records.
    /// - Returns: The subset of identities CloudKit reported as saved.
    /// - Throws: Encoding or CloudKit errors that prevent the export attempt.
    public func export(
        entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) async throws -> CloudLibrarySyncExportResult {
        let preparedRecords = try prepareRecords(
            for: entries,
            localSnapshotsByIdentity: localSnapshotsByIdentity
        )
        let savedRecordIDs = try await database.save(records: Array(preparedRecords.recordsByIdentity.values))
        let exportedIdentities = Set(
            savedRecordIDs.compactMap { recordID in
                preparedRecords.recordsByIdentity.first { $0.value.recordID == recordID }?.key
            })
        let partialFailureCount = max(0, preparedRecords.recordsByIdentity.count - savedRecordIDs.count)
        if partialFailureCount > 0 {
            cloudLibrarySyncExportLogger.warning(
                "Only \(savedRecordIDs.count, privacy: .public) of \(preparedRecords.recordsByIdentity.count, privacy: .public) iCloud sync records were accepted by CloudKit."
            )
        }
        return .init(exportedIdentities: exportedIdentities)
    }

    private struct PreparedRecords {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord]
    }

    /// Converts dirty entries into CloudKit records, skipping upserts whose
    /// local snapshots no longer exist.
    private func prepareRecords(
        for entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) throws -> PreparedRecords {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord] = [:]

        for entry in entries {
            switch entry {
            case .upsert(let pendingUpsert):
                guard let snapshot = localSnapshotsByIdentity[pendingUpsert.identity] else {
                    continue
                }
                recordsByIdentity[pendingUpsert.identity] = try client.record(from: snapshot)
            case .delete(let pendingDelete):
                recordsByIdentity[pendingDelete.identity] = try client.record(from: pendingDelete.tombstone)
            }
        }

        return .init(
            recordsByIdentity: recordsByIdentity
        )
    }
}
