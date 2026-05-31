//
//  CloudLibrarySyncExporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation

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
        let recordsByIdentity = try records(
            for: entries,
            localSnapshotsByIdentity: localSnapshotsByIdentity
        )
        let savedRecordIDs = try await database.save(records: Array(recordsByIdentity.values))
        let exportedIdentities = Set(savedRecordIDs.compactMap { recordID in
            recordsByIdentity.first { $0.value.recordID == recordID }?.key
        })
        return .init(exportedIdentities: exportedIdentities)
    }

    public func records(
        for entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) throws -> [LibraryEntrySyncIdentity: CKRecord] {
        var recordsByIdentity: [LibraryEntrySyncIdentity: CKRecord] = [:]

        for entry in entries {
            switch entry {
            case .upsert(let pendingUpsert):
                guard let snapshot = localSnapshotsByIdentity[pendingUpsert.identity] else {
                    continue
                }
                recordsByIdentity[pendingUpsert.identity] = try client.record(from: snapshot)
            case .delete(let pendingDelete):
                let snapshot = pendingDelete.tombstone.syncSnapshot()
                recordsByIdentity[pendingDelete.identity] = try client.record(from: snapshot)
            }
        }

        return recordsByIdentity
    }
}
