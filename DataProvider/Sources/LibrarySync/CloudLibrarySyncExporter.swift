//
//  CloudLibrarySyncExporter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import DataProvider
import Foundation
import os

fileprivate let cloudLibrarySyncExportLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.Export"
)

/// Result of pushing queued local changes to CloudKit.
public struct CloudLibrarySyncExportResult: Sendable {
    public var exportedIdentities: Set<LibraryEntryIdentity>
    public var settingsExported: Bool

    /// Creates the export result from the identities CloudKit accepted.
    public init(exportedIdentities: Set<LibraryEntryIdentity>, settingsExported: Bool = false) {
        self.exportedIdentities = exportedIdentities
        self.settingsExported = settingsExported
    }
}

/// Export failure that preserves records CloudKit accepted before a later
/// request failed.
public struct CloudLibrarySyncExportFailure: Error {
    public var partialResult: CloudLibrarySyncExportResult
    public var underlyingError: any Error

    public init(
        partialResult: CloudLibrarySyncExportResult,
        underlyingError: any Error
    ) {
        self.partialResult = partialResult
        self.underlyingError = underlyingError
    }
}

extension CloudLibrarySyncExportFailure: LocalizedError {
    public var errorDescription: String? {
        underlyingError.localizedDescription
    }
}

/// Builds CloudKit records from local dirty-queue entries and submits them.
public struct CloudLibrarySyncExporter: @unchecked Sendable {
    static let maxRecordsPerModifyRequest = 350

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
    ///   - settingsSnapshot: Optional settings snapshot to export alongside the
    ///     library entry records.
    /// - Returns: The subset of identities CloudKit reported as saved.
    /// - Throws: Encoding or CloudKit errors that prevent the export attempt.
    public func export(
        entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntryIdentity: LibraryEntrySyncSnapshot],
        settingsSnapshot: LibrarySettingsSyncSnapshot? = nil
    ) async throws -> CloudLibrarySyncExportResult {
        let preparedRecords = try prepareRecords(
            for: entries,
            localSnapshotsByIdentity: localSnapshotsByIdentity,
            settingsSnapshot: settingsSnapshot
        )
        let recordsToSave =
            Array(preparedRecords.recordsByIdentity.values)
            + (preparedRecords.settingsRecord.map { [$0] } ?? [])
        let identitiesByRecordID = preparedRecords.recordsByIdentity.reduce(
            into: [CKRecord.ID: LibraryEntryIdentity]()
        ) { identitiesByRecordID, pair in
            identitiesByRecordID[pair.value.recordID] = pair.key
        }

        let savedRecordIDs: [CKRecord.ID]
        do {
            savedRecordIDs = try await saveRecords(recordsToSave)
        } catch let failure as CloudLibrarySyncSaveProgressFailure {
            guard !failure.savedRecordIDs.isEmpty else {
                throw failure.underlyingError
            }
            throw CloudLibrarySyncExportFailure(
                partialResult: exportResult(
                    savedRecordIDs: failure.savedRecordIDs,
                    identitiesByRecordID: identitiesByRecordID
                ),
                underlyingError: failure.underlyingError
            )
        }
        let exportResult = exportResult(
            savedRecordIDs: savedRecordIDs,
            identitiesByRecordID: identitiesByRecordID
        )
        logPartialFailures(
            savedRecordIDs: savedRecordIDs,
            preparedRecordCount: preparedRecords.recordsByIdentity.count
                + (preparedRecords.settingsRecord == nil ? 0 : 1)
        )
        return exportResult
    }

    private func exportResult(
        savedRecordIDs: [CKRecord.ID],
        identitiesByRecordID: [CKRecord.ID: LibraryEntryIdentity]
    ) -> CloudLibrarySyncExportResult {
        let exportedIdentities = Set(
            savedRecordIDs.compactMap { recordID in identitiesByRecordID[recordID] }
        )

        return .init(
            exportedIdentities: exportedIdentities,
            settingsExported: savedRecordIDs.contains(client.librarySettingsRecordID)
        )
    }

    private func logPartialFailures(
        savedRecordIDs: [CKRecord.ID],
        preparedRecordCount: Int
    ) {
        let partialFailureCount = max(0, preparedRecordCount - savedRecordIDs.count)
        if partialFailureCount > 0 {
            cloudLibrarySyncExportLogger.warning(
                "Only \(savedRecordIDs.count, privacy: .public) of \(preparedRecordCount, privacy: .public) iCloud sync records were accepted by CloudKit."
            )
        }
    }

    private func saveRecords(_ records: [CKRecord]) async throws -> [CKRecord.ID] {
        guard !records.isEmpty else { return [] }

        var savedRecordIDs: [CKRecord.ID] = []
        var startIndex = records.startIndex
        while startIndex < records.endIndex {
            let endIndex = min(startIndex + Self.maxRecordsPerModifyRequest, records.endIndex)
            do {
                savedRecordIDs.append(
                    contentsOf: try await saveRecordBatch(Array(records[startIndex..<endIndex]))
                )
            } catch let failure as CloudLibrarySyncSaveProgressFailure {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: savedRecordIDs + failure.savedRecordIDs,
                    underlyingError: failure.underlyingError
                )
            } catch {
                guard !savedRecordIDs.isEmpty else { throw error }
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: savedRecordIDs,
                    underlyingError: error
                )
            }
            startIndex = endIndex
        }
        return savedRecordIDs
    }

    private func saveRecordBatch(_ records: [CKRecord]) async throws -> [CKRecord.ID] {
        do {
            return try await database.save(records: records)
        } catch {
            guard error.isCloudLibrarySyncLimitExceeded, records.count > 1 else {
                throw error
            }

            let splitIndex = records.index(records.startIndex, offsetBy: records.count / 2)
            let firstSavedRecordIDs = try await saveRecordBatch(Array(records[..<splitIndex]))
            do {
                return firstSavedRecordIDs + (try await saveRecordBatch(Array(records[splitIndex...])))
            } catch let failure as CloudLibrarySyncSaveProgressFailure {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: firstSavedRecordIDs + failure.savedRecordIDs,
                    underlyingError: failure.underlyingError
                )
            } catch {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: firstSavedRecordIDs,
                    underlyingError: error
                )
            }
        }
    }

    private struct PreparedRecords {
        var recordsByIdentity: [LibraryEntryIdentity: CKRecord]
        var settingsRecord: CKRecord?
    }

    /// Converts dirty entries into CloudKit records, skipping upserts whose
    /// local snapshots no longer exist.
    private func prepareRecords(
        for entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntryIdentity: LibraryEntrySyncSnapshot],
        settingsSnapshot: LibrarySettingsSyncSnapshot?
    ) throws -> PreparedRecords {
        var recordsByIdentity: [LibraryEntryIdentity: CKRecord] = [:]

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

fileprivate struct CloudLibrarySyncSaveProgressFailure: Error {
    var savedRecordIDs: [CKRecord.ID]
    var underlyingError: any Error
}

extension Error {
    fileprivate var isCloudLibrarySyncLimitExceeded: Bool {
        guard let ckError = self as? CKError else { return false }
        return ckError.code == .limitExceeded
    }
}
