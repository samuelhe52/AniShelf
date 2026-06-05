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
    public var settingsExported: Bool

    /// Creates the export result from the identities CloudKit accepted.
    public init(exportedIdentities: Set<LibraryEntrySyncIdentity>, settingsExported: Bool = false) {
        self.exportedIdentities = exportedIdentities
        self.settingsExported = settingsExported
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
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        settingsSnapshot: LibrarySettingsSyncSnapshot? = nil
    ) async throws -> CloudLibrarySyncExportResult {
        let preparedRecords = try prepareRecords(
            for: entries,
            localSnapshotsByIdentity: localSnapshotsByIdentity,
            settingsSnapshot: settingsSnapshot
        )
        let recordsToSave = Array(preparedRecords.recordsByIdentity.values)
            + (preparedRecords.settingsRecord.map { [$0] } ?? [])
        let savedRecordIDs = try await database.save(records: recordsToSave)
        let exportedIdentities = Set(
            savedRecordIDs.compactMap { recordID in
                preparedRecords.recordsByIdentity.first { $0.value.recordID == recordID }?.key
            })
        let preparedRecordCount = preparedRecords.recordsByIdentity.count + (preparedRecords.settingsRecord == nil ? 0 : 1)
        let partialFailureCount = max(0, preparedRecordCount - savedRecordIDs.count)
        if partialFailureCount > 0 {
            cloudLibrarySyncExportLogger.warning(
                "Only \(savedRecordIDs.count, privacy: .public) of \(preparedRecordCount, privacy: .public) iCloud sync records were accepted by CloudKit."
            )
        }
        return .init(
            exportedIdentities: exportedIdentities,
            settingsExported: settingsSnapshot != nil
                ? savedRecordIDs.contains(client.librarySettingsRecordID)
                : false
        )
    }

    private struct PreparedRecords {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord]
        var settingsRecord: CKRecord?
    }

    /// Converts dirty entries into CloudKit records, skipping upserts whose
    /// local snapshots no longer exist.
    private func prepareRecords(
        for entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        settingsSnapshot: LibrarySettingsSyncSnapshot?
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
            recordsByIdentity: recordsByIdentity,
            settingsRecord: try settingsSnapshot.map(client.record(from:))
        )
    }
}
