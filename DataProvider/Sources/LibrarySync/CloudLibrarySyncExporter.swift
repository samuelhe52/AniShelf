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
///
/// Rejected records are ones CloudKit refused, or did not confirm, for reasons
/// specific to each record. They stay queued locally for a later attempt.
public struct CloudLibrarySyncExportResult: Sendable {
    public var exportedIdentities: Set<LibraryEntryIdentity>
    public var settingsExported: Bool
    public var rejectedIdentities: Set<LibraryEntryIdentity>
    public var settingsRejected: Bool

    /// Creates the export result from the identities CloudKit accepted and rejected.
    public init(
        exportedIdentities: Set<LibraryEntryIdentity>,
        settingsExported: Bool = false,
        rejectedIdentities: Set<LibraryEntryIdentity> = [],
        settingsRejected: Bool = false
    ) {
        self.exportedIdentities = exportedIdentities
        self.settingsExported = settingsExported
        self.rejectedIdentities = rejectedIdentities
        self.settingsRejected = settingsRejected
    }

    /// Number of queued changes CloudKit rejected, counting settings as one.
    public var rejectedChangeCount: Int {
        rejectedIdentities.count + (settingsRejected ? 1 : 0)
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
    ///   - blockedRecordIDs: Quarantined records that this build must not overwrite.
    /// - Returns: The identities CloudKit saved, and those it rejected one
    ///   record at a time.
    /// - Throws: Encoding errors, or CloudKit errors that affect the whole
    ///   export, such as network, account, quota, or throttling failures.
    public func export(
        entries: [LibraryEntrySyncDirtyQueueEntry],
        localSnapshotsByIdentity: [LibraryEntryIdentity: LibraryEntrySyncSnapshot],
        settingsSnapshot: LibrarySettingsSyncSnapshot? = nil,
        blockedRecordIDs: Set<CKRecord.ID> = []
    ) async throws -> CloudLibrarySyncExportResult {
        let preparedRecords = try prepareRecords(
            for: entries,
            localSnapshotsByIdentity: localSnapshotsByIdentity,
            settingsSnapshot: settingsSnapshot,
            blockedRecordIDs: blockedRecordIDs
        )
        let recordsToSave =
            Array(preparedRecords.recordsByIdentity.values)
            + (preparedRecords.settingsRecord.map { [$0] } ?? [])
        let identitiesByRecordID = preparedRecords.recordsByIdentity.reduce(
            into: [CKRecord.ID: LibraryEntryIdentity]()
        ) { identitiesByRecordID, pair in
            identitiesByRecordID[pair.value.recordID] = pair.key
        }

        let progress: SaveProgress
        do {
            progress = try await saveRecords(recordsToSave)
        } catch let failure as CloudLibrarySyncSaveProgressFailure {
            guard !failure.savedRecordIDs.isEmpty else {
                throw failure.underlyingError
            }
            throw CloudLibrarySyncExportFailure(
                partialResult: exportResult(
                    for: SaveProgress(savedRecordIDs: failure.savedRecordIDs),
                    identitiesByRecordID: identitiesByRecordID
                ),
                underlyingError: failure.underlyingError
            )
        }
        logRejectedRecords(progress, preparedRecordCount: recordsToSave.count)
        return exportResult(for: progress, identitiesByRecordID: identitiesByRecordID)
    }

    private func exportResult(
        for progress: SaveProgress,
        identitiesByRecordID: [CKRecord.ID: LibraryEntryIdentity]
    ) -> CloudLibrarySyncExportResult {
        .init(
            exportedIdentities: Set(progress.savedRecordIDs.compactMap { identitiesByRecordID[$0] }),
            settingsExported: progress.savedRecordIDs.contains(client.librarySettingsRecordID),
            rejectedIdentities: Set(progress.rejectedErrorsByID.keys.compactMap { identitiesByRecordID[$0] }),
            settingsRejected: progress.rejectedErrorsByID[client.librarySettingsRecordID] != nil
        )
    }

    private func logRejectedRecords(_ progress: SaveProgress, preparedRecordCount: Int) {
        guard !progress.rejectedErrorsByID.isEmpty else { return }
        let reasons = Set(progress.rejectedErrorsByID.values.map(\.cloudLibrarySyncLogDescription))
            .sorted()
            .joined(separator: ", ")
        cloudLibrarySyncExportLogger.warning(
            "CloudKit rejected \(progress.rejectedErrorsByID.count, privacy: .public) of \(preparedRecordCount, privacy: .public) iCloud sync records; they stay queued for retry: \(reasons, privacy: .public)"
        )
    }

    private func saveRecords(_ records: [CKRecord]) async throws -> SaveProgress {
        var progress = SaveProgress()
        var startIndex = records.startIndex
        while startIndex < records.endIndex {
            let endIndex = min(startIndex + Self.maxRecordsPerModifyRequest, records.endIndex)
            do {
                progress.append(try await saveRecordBatch(Array(records[startIndex..<endIndex])))
            } catch let failure as CloudLibrarySyncSaveProgressFailure {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: progress.savedRecordIDs + failure.savedRecordIDs,
                    underlyingError: failure.underlyingError
                )
            } catch {
                guard !progress.savedRecordIDs.isEmpty else { throw error }
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: progress.savedRecordIDs,
                    underlyingError: error
                )
            }
            startIndex = endIndex
        }
        return progress
    }

    /// Saves one request's worth of records.
    ///
    /// Failures that concern single records are returned as rejections so the
    /// remaining batches still run. Any other failure throws.
    private func saveRecordBatch(_ records: [CKRecord]) async throws -> SaveProgress {
        do {
            let requestedRecordIDs = Set(records.map(\.recordID))
            let savedRecordIDs = Set(try await database.save(records: records))
                .intersection(requestedRecordIDs)
            return SaveProgress(records: records, savedRecordIDs: savedRecordIDs)
        } catch let partialFailure as CloudLibrarySyncPartialSaveFailure {
            guard partialFailure.isRecordScoped else {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: partialFailure.savedRecordIDs,
                    underlyingError: partialFailure
                )
            }
            return SaveProgress(
                records: records,
                savedRecordIDs: Set(partialFailure.savedRecordIDs),
                rejectedErrorsByID: partialFailure.failedErrorsByID
            )
        } catch {
            guard error.isCloudLibrarySyncLimitExceeded else {
                throw error
            }
            guard records.count > 1 else {
                // A single record over CloudKit's size limit cannot save as is,
                // but it should not hold back the rest of the library.
                return SaveProgress(
                    records: records,
                    savedRecordIDs: [],
                    rejectedErrorsByID: [records[0].recordID: error]
                )
            }

            let splitIndex = records.index(records.startIndex, offsetBy: records.count / 2)
            var progress = try await saveRecordBatch(Array(records[..<splitIndex]))
            do {
                progress.append(try await saveRecordBatch(Array(records[splitIndex...])))
                return progress
            } catch let failure as CloudLibrarySyncSaveProgressFailure {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: progress.savedRecordIDs + failure.savedRecordIDs,
                    underlyingError: failure.underlyingError
                )
            } catch {
                throw CloudLibrarySyncSaveProgressFailure(
                    savedRecordIDs: progress.savedRecordIDs,
                    underlyingError: error
                )
            }
        }
    }

    private struct SaveProgress {
        var savedRecordIDs: [CKRecord.ID] = []
        var rejectedErrorsByID: [CKRecord.ID: any Error] = [:]

        init(savedRecordIDs: [CKRecord.ID] = []) {
            self.savedRecordIDs = savedRecordIDs
        }

        /// Classifies every requested record as saved or rejected.
        ///
        /// A record CloudKit neither confirmed nor rejected counts as rejected,
        /// since keeping it queued for another save is safer than dropping it.
        init(
            records: [CKRecord],
            savedRecordIDs: Set<CKRecord.ID>,
            rejectedErrorsByID: [CKRecord.ID: any Error] = [:]
        ) {
            for record in records {
                if savedRecordIDs.contains(record.recordID) {
                    self.savedRecordIDs.append(record.recordID)
                } else {
                    self.rejectedErrorsByID[record.recordID] =
                        rejectedErrorsByID[record.recordID] ?? CloudLibrarySyncUnconfirmedSaveError()
                }
            }
        }

        mutating func append(_ other: SaveProgress) {
            savedRecordIDs += other.savedRecordIDs
            rejectedErrorsByID.merge(other.rejectedErrorsByID) { current, _ in current }
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
        settingsSnapshot: LibrarySettingsSyncSnapshot?,
        blockedRecordIDs: Set<CKRecord.ID>
    ) throws -> PreparedRecords {
        var recordsByIdentity: [LibraryEntryIdentity: CKRecord] = [:]

        for entry in entries where !blockedRecordIDs.contains(client.recordID(for: entry.identity)) {
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
            settingsRecord: blockedRecordIDs.contains(client.librarySettingsRecordID)
                ? nil : try settingsSnapshot.map(client.record(from:))
        )
    }
}

fileprivate struct CloudLibrarySyncUnconfirmedSaveError: LocalizedError {
    var errorDescription: String? {
        "CloudKit did not confirm every library sync record save."
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

    fileprivate var cloudLibrarySyncLogDescription: String {
        let error = self as NSError
        return "\(error.domain):\(error.code)"
    }
}
