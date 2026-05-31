//
//  CloudLibrarySyncExporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import os

private let cloudLibrarySyncExportLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.Export"
)

public struct CloudLibrarySyncExportResult {
    public var exportedIdentities: Set<LibraryEntrySyncIdentity>

    public init(exportedIdentities: Set<LibraryEntrySyncIdentity>) {
        self.exportedIdentities = exportedIdentities
    }
}

public struct CloudLibrarySyncExporter: @unchecked Sendable {
    private let client: CloudLibrarySyncClient
    private let database: CloudLibrarySyncDatabase

    public init(
        client: CloudLibrarySyncClient,
        database: CloudLibrarySyncDatabase
    ) {
        self.client = client
        self.database = database
    }

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
        let exportedIdentities = Set(savedRecordIDs.compactMap { recordID in
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

    public func records(
        for entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) throws -> [LibraryEntrySyncIdentity: CKRecord] {
        try prepareRecords(for: entries, localSnapshotsByIdentity: localSnapshotsByIdentity).recordsByIdentity
    }

    private struct PreparedRecords {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord]
        var skippedMissingLocalSnapshotCount: Int
        var upsertRecordCount: Int
        var tombstoneRecordCount: Int
    }

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
