//
//  CloudLibrarySyncImporterExporterTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/31.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync

struct CloudLibrarySyncImporterExporterTests {
    private let client = CloudLibrarySyncClient()

    @Test func importerCoalescesRemoteChangesAndCommitsTokenOnlyExplicitly() async throws {
        let namespace = makeNamespace()
        let suiteName = "CloudLibrarySyncImporterExporterTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let firstToken = try makeToken()
        let finalToken = try makeToken()
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 901)
        let olderSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 901,
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 1),
            notes: "Older"
        )
        let newerSnapshot = makeSnapshot(
            identity: identity,
            tmdbID: 901,
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 2),
            notes: "Newer"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: olderSnapshot)],
                deletedRecordIDs: [],
                changeToken: firstToken,
                moreComing: true
            ),
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: newerSnapshot)],
                deletedRecordIDs: [],
                changeToken: finalToken,
                moreComing: false
            )
        ])
        let importer = CloudLibrarySyncImporter(
            client: client,
            database: database,
            changeTokenStore: tokenStore
        )

        let batch = try await importer.fetchChanges(
            namespace: namespace,
            localSnapshotsByIdentity: [:]
        )

        #expect(batch.changes.count == 1)
        if case .snapshot(let snapshot)? = batch.changes.first {
            #expect(snapshot.notes == "Newer")
        } else {
            #expect(Bool(false))
        }
        #expect(database.requestedTokens.count == 2)
        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)

        try importer.commit(batch)

        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) != nil)
    }

    @Test func importerResetsExpiredTokenAndRetriesFromNil() async throws {
        let namespace = makeNamespace()
        let suiteName = "CloudLibrarySyncImporterExporterTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let expiredToken = try makeToken()
        let finalToken = try makeToken()
        tokenStore.setToken(expiredToken, for: CloudLibrarySyncClient.recordZoneID, namespace: namespace)

        let identity = LibraryEntryIdentity(entryType: .movie, tmdbID: 902)
        let database = FakeCloudLibrarySyncDatabase(
            changes: [
                .init(
                    modifiedRecordsByID: [
                        client.recordID(for: identity): try client.record(
                            from: makeSnapshot(
                                identity: identity,
                                tmdbID: 902,
                                entryType: .movie
                            ))
                    ],
                    deletedRecordIDs: [],
                    changeToken: finalToken,
                    moreComing: false
                )
            ],
            firstFetchError: CKError(.changeTokenExpired)
        )
        let importer = CloudLibrarySyncImporter(
            client: client,
            database: database,
            changeTokenStore: tokenStore
        )

        let batch = try await importer.fetchChanges(
            namespace: namespace,
            localSnapshotsByIdentity: [:]
        )

        #expect(batch.changes.count == 1)
        #expect(database.requestedTokens.count == 2)
        if let requestedToken = database.requestedTokens[0] {
            #expect(try tokenStore.encodeToken(requestedToken) == tokenStore.encodeToken(expiredToken))
        } else {
            #expect(Bool(false))
        }
        #expect(database.requestedTokens[1] == nil)
    }

    @Test func importerReturnsLeanTombstonesAndIgnoresRawDeletes() async throws {
        let namespace = makeNamespace()
        let suiteName = "CloudLibrarySyncImporterExporterTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let finalToken = try makeToken()
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 903)
        let tombstone = LibraryEntrySyncTombstone(
            identity: identity,
            tmdbID: 903,
            parentSeriesID: nil,
            seasonNumber: nil,
            entryType: .series,
            deletedAt: referenceDate(year: 2026, month: 5, day: 9)
        )
        let rawDeleteID = CKRecord.ID(
            recordName: "series:904",
            zoneID: CloudLibrarySyncClient.recordZoneID
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: identity): try client.record(from: tombstone)],
                deletedRecordIDs: [rawDeleteID],
                changeToken: finalToken,
                moreComing: false
            )
        ])
        let importer = CloudLibrarySyncImporter(
            client: client,
            database: database,
            changeTokenStore: tokenStore
        )

        let batch = try await importer.fetchChanges(
            namespace: namespace,
            localSnapshotsByIdentity: [:]
        )

        #expect(batch.changes.first == .tombstone(tombstone))
        #expect(batch.ignoredDeletedRecordIDs == [rawDeleteID])
    }

    @Test func librarySettingsRecordRoundTripsAndRejectsUnsupportedSchema() throws {
        let snapshot = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [
                "UseTMDbRelayServer": .bool(true),
                "LibraryDefaultFilters": .stringArray(["favorited", "watched"]),
                "PreferredAnimeInfoLanguage": .string("ja")
            ]
        )

        let record = try client.record(from: snapshot)
        let decoded = try client.settingsSnapshot(from: record)

        #expect(decoded == snapshot)

        record["schemaVersion"] = LibrarySettingsSyncSnapshot.currentSchemaVersion + 1
        #expect(
            throws: CloudLibrarySyncDecodeError.unsupportedSchemaVersion(
                LibrarySettingsSyncSnapshot.currentSchemaVersion + 1)
        ) {
            try client.settingsSnapshot(from: record)
        }
    }

    @Test func librarySettingsRecordKeepsUnknownJSONValues() throws {
        let record = try client.record(
            from: .init(
                updatedAt: referenceDate(year: 2026, month: 6, day: 5),
                payload: ["Known": .bool(true)]
            ))
        let payloadJSON =
            #"{"Known":true,"FutureNumber":42.5,"FutureObject":{"enabled":false,"items":[1,null]},"FutureArray":[1,"x"]}"#
        record["payload"] = Data(payloadJSON.utf8)

        let snapshot = try client.settingsSnapshot(from: record)
        let futureNumber = try #require(Decimal(string: "42.5"))

        #expect(snapshot.payload["Known"] == .bool(true))
        #expect(snapshot.payload["FutureNumber"] == .unknown(.number(futureNumber)))
        #expect(
            snapshot.payload["FutureObject"]
                == .unknown(
                    .object([
                        "enabled": .bool(false), "items": .array([.number(1), .null])
                    ])))
        #expect(snapshot.payload["FutureArray"] == .unknown(.array([.number(1), .string("x")])))
        #expect(try client.settingsSnapshot(from: client.record(from: snapshot)) == snapshot)
    }

    @Test func importerDecodesMixedEntryAndSettingsBatch() async throws {
        let namespace = makeNamespace()
        let suiteName = "CloudLibrarySyncImporterExporterTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let entryIdentity = LibraryEntryIdentity(entryType: .movie, tmdbID: 904)
        let entrySnapshot = makeSnapshot(identity: entryIdentity, tmdbID: 904, entryType: .movie)
        let settingsSnapshot = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: ["UseTMDbRelayServer": .bool(true)]
        )
        // A later page carries the newer server version even when the writing
        // device's clock was behind.
        let replacedSettingsSnapshot = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 7),
            payload: ["UseTMDbRelayServer": .bool(false)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.librarySettingsRecordID: try client.record(from: replacedSettingsSnapshot)
                ],
                deletedRecordIDs: [],
                changeToken: try makeToken(),
                moreComing: true
            ),
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: entryIdentity): try client.record(from: entrySnapshot),
                    client.librarySettingsRecordID: try client.record(from: settingsSnapshot)
                ],
                deletedRecordIDs: [],
                changeToken: try makeToken(),
                moreComing: false
            )
        ])
        let importer = CloudLibrarySyncImporter(
            client: client,
            database: database,
            changeTokenStore: tokenStore
        )

        let batch = try await importer.fetchChanges(
            namespace: namespace,
            localSnapshotsByIdentity: [:]
        )

        #expect(batch.changes == [.snapshot(entrySnapshot)])
        #expect(batch.settingsSnapshot == settingsSnapshot)
    }

    @Test func exporterSavesDeleteTombstonesAsRecordUpsertsAndReportsPartialSuccess() async throws {
        let first = AnimeEntry(name: "First", type: .movie, tmdbID: 905)
        let second = AnimeEntry(name: "Second", type: .series, tmdbID: 906)
        let firstSnapshot = LibraryEntrySyncSnapshot(entry: first)
        let tombstone = LibraryEntrySyncTombstone(
            entry: second,
            deletedAt: referenceDate(year: 2026, month: 5, day: 10)
        )
        let database = FakeCloudLibrarySyncDatabase(
            changes: [],
            successfulSaveRecordIDs: [client.recordID(for: first.libraryIdentity)]
        )
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        // An unconfirmed save stays queued for retry without failing the export.
        let result = try await exporter.export(
            entries: [
                .upsert(
                    .init(identity: first.libraryIdentity, dirtyAt: referenceDate(year: 2026, month: 5, day: 8))),
                .delete(.init(tombstone: tombstone))
            ],
            localSnapshotsByIdentity: [first.libraryIdentity: firstSnapshot]
        )
        #expect(result.exportedIdentities == [first.libraryIdentity])
        #expect(result.rejectedIdentities == [second.libraryIdentity])
        #expect(database.savedRecords.count == 2)
        let savedTombstoneRecord = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: second.libraryIdentity) }
        )
        let savedTombstoneChange = try client.remoteChange(from: savedTombstoneRecord)
        #expect(savedTombstoneChange == .tombstone(tombstone))
        #expect(!savedTombstoneRecord.allKeys().contains("notes"))
        #expect(!savedTombstoneRecord.allKeys().contains("episodeProgresses"))
        #expect(!savedTombstoneRecord.allKeys().contains("watchStatus"))
    }

    @Test func exporterBatchesLargeLibrariesUnderCloudKitRequestLimit() async throws {
        let payload = makeExportPayload(count: 574)
        let settingsSnapshot = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 12),
            payload: ["UseTMDbRelayServer": .bool(true)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        let result = try await exporter.export(
            entries: payload.entries,
            localSnapshotsByIdentity: payload.snapshots,
            settingsSnapshot: settingsSnapshot
        )

        #expect(database.saveBatchSizes == [350, 225])
        #expect(
            database.saveBatchSizes.allSatisfy {
                $0 <= CloudLibrarySyncExporter.maxRecordsPerModifyRequest
            }
        )
        #expect(database.savedRecords.count == 575)
        #expect(result.exportedIdentities == Set(payload.identities))
        #expect(result.settingsExported)
    }

    @Test func exporterRecursivelySplitsBatchesWhenCloudKitLimitChanges() async throws {
        let payload = makeExportPayload(count: 360, startingTMDbID: 30_000)
        let database = FakeCloudLibrarySyncDatabase(
            changes: [],
            maxSaveBatchSizeBeforeLimitExceeded: 100
        )
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        let result = try await exporter.export(
            entries: payload.entries,
            localSnapshotsByIdentity: payload.snapshots
        )

        #expect(database.saveBatchSizes == [350, 175, 87, 88, 175, 87, 88, 10])
        #expect(database.savedRecords.count == 360)
        #expect(result.exportedIdentities == Set(payload.identities))
    }

    @Test func exporterFailurePreservesAcceptedIDsFromEarlierBatches() async throws {
        let payload = makeExportPayload(count: 360, startingTMDbID: 40_000)
        let database = FakeCloudLibrarySyncDatabase(
            changes: [],
            saveErrorsByCallIndex: [2: CKError(.networkFailure)]
        )
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        do {
            _ = try await exporter.export(
                entries: payload.entries,
                localSnapshotsByIdentity: payload.snapshots
            )
            Issue.record("Expected export to fail after preserving the first accepted batch.")
        } catch let failure as CloudLibrarySyncExportFailure {
            #expect(database.saveBatchSizes == [350, 10])
            #expect(failure.partialResult.exportedIdentities.count == 350)
            #expect(!failure.partialResult.settingsExported)
            #expect((failure.underlyingError as? CKError)?.code == .networkFailure)
        }
    }

    @Test func exporterContinuesPastRecordRejectedByCloudKit() async throws {
        let payload = makeExportPayload(count: 360, startingTMDbID: 42_000)
        let rejected = try #require(payload.identities.first)
        let database = FakeCloudLibrarySyncDatabase(
            changes: [],
            rejectedSaveRecordIDs: [client.recordID(for: rejected)]
        )
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        let result = try await exporter.export(
            entries: payload.entries,
            localSnapshotsByIdentity: payload.snapshots
        )

        #expect(database.saveBatchSizes == [350, 10])
        #expect(result.exportedIdentities == Set(payload.identities).subtracting([rejected]))
        #expect(result.rejectedIdentities == [rejected])
    }

    @Test func exporterKeepsAcceptedIDsAndRetryHintFromPartialSave() async throws {
        let payload = makeExportPayload(count: 2, startingTMDbID: 45_000)
        let accepted = try #require(payload.identities.first)
        let failed = try #require(payload.identities.last)
        let partialFailure = CloudLibrarySyncPartialSaveFailure(
            savedRecordIDs: [client.recordID(for: accepted)],
            failedErrorsByID: [
                client.recordID(for: failed): CKError(
                    .requestRateLimited,
                    userInfo: [CKErrorRetryAfterKey: 42.0]
                )
            ]
        )
        let database = FakeCloudLibrarySyncDatabase(
            changes: [], saveErrorsByCallIndex: [1: partialFailure]
        )
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        do {
            _ = try await exporter.export(
                entries: payload.entries,
                localSnapshotsByIdentity: payload.snapshots
            )
            Issue.record("Expected the partial CloudKit failure to retain retry information.")
        } catch let failure as CloudLibrarySyncExportFailure {
            #expect(failure.partialResult.exportedIdentities == [accepted])
            #expect((failure.underlyingError as? CloudLibrarySyncPartialSaveFailure)?.retryAfterSeconds == 42)
        }
    }

    @Test func mixedQuotaAndTransientSaveFailuresRemainRetryable() {
        let quotaID = client.recordID(for: .init(entryType: .series, tmdbID: 45_010))
        let busyID = client.recordID(for: .init(entryType: .series, tmdbID: 45_011))
        let failure = CloudLibrarySyncPartialSaveFailure(
            savedRecordIDs: [],
            failedErrorsByID: [
                quotaID: CKError(.quotaExceeded),
                busyID: CKError(.zoneBusy, userInfo: [CKErrorRetryAfterKey: 30.0])
            ]
        )

        #expect(!failure.isQuotaExceeded)
        #expect(failure.retryAfterSeconds == 30)
    }

    @Test func exporterIncludesOptionalSettingsSnapshot() async throws {
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 907)
        let snapshot = makeSnapshot(identity: identity, tmdbID: 907)
        let settingsSnapshot = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: ["UseTMDbRelayServer": .bool(true)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        let result = try await exporter.export(
            entries: [.upsert(.init(identity: identity, dirtyAt: referenceDate(year: 2026, month: 6, day: 4)))],
            localSnapshotsByIdentity: [identity: snapshot],
            settingsSnapshot: settingsSnapshot
        )

        #expect(result.exportedIdentities == [identity])
        #expect(result.settingsExported)
        let savedSettingsRecord = try #require(
            database.savedRecords.first { $0.recordID == client.librarySettingsRecordID }
        )
        #expect(try client.settingsSnapshot(from: savedSettingsRecord) == settingsSnapshot)
    }

    @Test func importerQuarantinesBadRecordsAndExporterPreservesThem() async throws {
        let suiteName = "CloudLibrarySyncQuarantine.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: defaults)
        let quarantineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudLibrarySyncQuarantine.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: quarantineURL) }
        let quarantineStore = CloudLibrarySyncQuarantineStore(url: quarantineURL)
        let goodIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 1001)
        let badIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 1002)
        let good = makeSnapshot(identity: goodIdentity, tmdbID: 1001)
        let bad = makeSnapshot(identity: badIdentity, tmdbID: 1002)
        let badRecord = try client.record(from: bad)
        badRecord["schemaVersion"] = LibraryEntrySyncSnapshot.currentSchemaVersion + 1
        let settings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: ["UseTMDbRelayServer": .bool(true)]
        )
        let badSettings = try client.record(from: settings)
        badSettings["schemaVersion"] = LibrarySettingsSyncSnapshot.currentSchemaVersion + 1
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [
                    client.recordID(for: goodIdentity): try client.record(from: good),
                    client.recordID(for: badIdentity): badRecord,
                    client.librarySettingsRecordID: badSettings
                ],
                deletedRecordIDs: [],
                changeToken: try makeToken(),
                moreComing: false
            )
        ])
        let importer = CloudLibrarySyncImporter(
            client: client, database: database,
            changeTokenStore: tokenStore, quarantineStore: quarantineStore
        )
        let namespace = makeNamespace()
        let batch = try await importer.fetchChanges(namespace: namespace, localSnapshotsByIdentity: [:])
        #expect(batch.changes == [.snapshot(good)])
        #expect(batch.quarantinedRecordIDs == [client.recordID(for: badIdentity), client.librarySettingsRecordID])
        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)
        #expect(
            try quarantineStore.entries(namespace: namespace, zoneID: CloudLibrarySyncClient.recordZoneID).isEmpty)
        try importer.commit(batch)
        #expect(
            try quarantineStore.entries(namespace: namespace, zoneID: CloudLibrarySyncClient.recordZoneID).count == 2)
        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) != nil)

        let exporter = CloudLibrarySyncExporter(client: client, database: database)
        let result = try await exporter.export(
            entries: [
                .upsert(.init(identity: goodIdentity, dirtyAt: good.dateSaved)),
                .upsert(.init(identity: badIdentity, dirtyAt: bad.dateSaved))
            ],
            localSnapshotsByIdentity: [goodIdentity: good, badIdentity: bad],
            settingsSnapshot: settings,
            blockedRecordIDs: batch.quarantinedRecordIDs
        )
        #expect(result.exportedIdentities == [goodIdentity])
        #expect(!result.settingsExported)
        #expect(database.savedRecords.map(\.recordID) == [client.recordID(for: goodIdentity)])

        let otherNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: namespace.containerIdentifier,
            accountIdentifier: "other-account"
        )
        #expect(
            try quarantineStore.entries(namespace: otherNamespace, zoneID: CloudLibrarySyncClient.recordZoneID).isEmpty)
    }

    @Test func newAppVersionRefetchesQuarantinedRecordByID() async throws {
        let suiteName = "CloudLibrarySyncUpgrade.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: defaults)
        let quarantineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudLibrarySyncUpgrade.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: quarantineURL) }
        let quarantineStore = CloudLibrarySyncQuarantineStore(url: quarantineURL)
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 1011)
        let snapshot = makeSnapshot(identity: identity, tmdbID: 1011)
        let recordID = client.recordID(for: identity)
        let unreadableRecord = try client.record(from: snapshot)
        unreadableRecord["schemaVersion"] = LibraryEntrySyncSnapshot.currentSchemaVersion + 1
        let firstDatabase = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [recordID: unreadableRecord],
                deletedRecordIDs: [],
                changeToken: try makeToken(),
                moreComing: false
            )
        ])
        let firstImporter = CloudLibrarySyncImporter(
            client: client, database: firstDatabase,
            changeTokenStore: tokenStore, quarantineStore: quarantineStore,
            appVersion: "1"
        )
        let namespace = makeNamespace()
        let first = try await firstImporter.fetchChanges(namespace: namespace, localSnapshotsByIdentity: [:])
        try firstImporter.commit(first)
        #expect(first.quarantinedRecordIDs == [recordID])

        let recoveredRecord = try client.record(from: snapshot)
        let secondDatabase = FakeCloudLibrarySyncDatabase(
            changes: [
                .init(
                    modifiedRecordsByID: [:], deletedRecordIDs: [],
                    changeToken: try makeToken(), moreComing: false
                )
            ],
            fetchedRecordsByID: [recordID: recoveredRecord]
        )
        let upgradedImporter = CloudLibrarySyncImporter(
            client: client, database: secondDatabase,
            changeTokenStore: tokenStore, quarantineStore: quarantineStore,
            appVersion: "2"
        )
        let recovered = try await upgradedImporter.fetchChanges(
            namespace: namespace, localSnapshotsByIdentity: [:]
        )
        #expect(secondDatabase.requestedRecordIDs == [[recordID]])
        #expect(recovered.changes == [.snapshot(snapshot)])
        #expect(recovered.quarantinedRecordIDs.isEmpty)
        #expect(try quarantineStore.entries(namespace: namespace, zoneID: CloudLibrarySyncClient.recordZoneID).count == 1)

        // Local application can fail before commit. The next pass must fetch
        // the recovered record by ID again even though zone changes are empty.
        let retryDatabase = FakeCloudLibrarySyncDatabase(
            changes: [
                .init(modifiedRecordsByID: [:], deletedRecordIDs: [],
                      changeToken: try makeToken(), moreComing: false)
            ],
            fetchedRecordsByID: [recordID: recoveredRecord]
        )
        let retryImporter = CloudLibrarySyncImporter(
            client: client, database: retryDatabase,
            changeTokenStore: tokenStore, quarantineStore: quarantineStore,
            appVersion: "2"
        )
        let retried = try await retryImporter.fetchChanges(namespace: namespace, localSnapshotsByIdentity: [:])
        #expect(retryDatabase.requestedRecordIDs == [[recordID]])
        #expect(retried.changes == [.snapshot(snapshot)])
        try retryImporter.commit(retried)
        #expect(try quarantineStore.entries(namespace: namespace, zoneID: CloudLibrarySyncClient.recordZoneID).isEmpty)
    }
}

fileprivate final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    private let firstFetchError: Error?
    private let successfulSaveRecordIDs: [CKRecord.ID]?
    private let maxSaveBatchSizeBeforeLimitExceeded: Int?
    private let saveErrorsByCallIndex: [Int: any Error]
    private let rejectedSaveRecordIDs: Set<CKRecord.ID>
    private let fetchedRecordsByID: [CKRecord.ID: CKRecord]
    private var didThrowFirstFetchError = false
    private var saveCallCount = 0

    var requestedTokens: [CKServerChangeToken?] = []
    var savedRecords: [CKRecord] = []
    var saveBatchSizes: [Int] = []
    var ensureCallCount = 0
    var requestedRecordIDs: [[CKRecord.ID]] = []

    init(
        changes: [CloudLibrarySyncZoneChangeBatch],
        firstFetchError: Error? = nil,
        successfulSaveRecordIDs: [CKRecord.ID]? = nil,
        maxSaveBatchSizeBeforeLimitExceeded: Int? = nil,
        saveErrorsByCallIndex: [Int: any Error] = [:],
        rejectedSaveRecordIDs: Set<CKRecord.ID> = [],
        fetchedRecordsByID: [CKRecord.ID: CKRecord] = [:]
    ) {
        self.changes = changes
        self.firstFetchError = firstFetchError
        self.successfulSaveRecordIDs = successfulSaveRecordIDs
        self.maxSaveBatchSizeBeforeLimitExceeded = maxSaveBatchSizeBeforeLimitExceeded
        self.saveErrorsByCallIndex = saveErrorsByCallIndex
        self.rejectedSaveRecordIDs = rejectedSaveRecordIDs
        self.fetchedRecordsByID = fetchedRecordsByID
    }

    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        ensureCallCount += 1
    }

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        requestedTokens.append(changeToken)
        if let firstFetchError, !didThrowFirstFetchError {
            didThrowFirstFetchError = true
            throw firstFetchError
        }
        return changes.removeFirst()
    }

    func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        saveCallCount += 1
        saveBatchSizes.append(records.count)
        if let error = saveErrorsByCallIndex[saveCallCount] {
            throw error
        }
        if let maxSaveBatchSizeBeforeLimitExceeded,
            records.count > maxSaveBatchSizeBeforeLimitExceeded
        {
            throw CKError(.limitExceeded)
        }
        let rejectedRecords = records.filter { rejectedSaveRecordIDs.contains($0.recordID) }
        if !rejectedRecords.isEmpty {
            let acceptedRecords = records.filter { !rejectedSaveRecordIDs.contains($0.recordID) }
            savedRecords.append(contentsOf: acceptedRecords)
            throw CloudLibrarySyncPartialSaveFailure(
                savedRecordIDs: acceptedRecords.map(\.recordID),
                failedErrorsByID: Dictionary(
                    uniqueKeysWithValues: rejectedRecords.map { ($0.recordID, CKError(.invalidArguments)) }
                )
            )
        }
        savedRecords.append(contentsOf: records)
        guard let successfulSaveRecordIDs else {
            return records.map(\.recordID)
        }
        let successfulSaveRecordIDSet = Set(successfulSaveRecordIDs)
        return records.map(\.recordID).filter { successfulSaveRecordIDSet.contains($0) }
    }

    func fetchRecords(ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        requestedRecordIDs.append(ids)
        return fetchedRecordsByID.filter { ids.contains($0.key) }
    }
}

fileprivate func makeNamespace() -> CloudLibrarySyncChangeTokenStore.Namespace {
    .init(
        containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
        accountIdentifier: "test-account"
    )
}

fileprivate func makeToken() throws -> CKServerChangeToken {
    try #require(class_createInstance(CKServerChangeToken.self, 0) as? CKServerChangeToken)
}

fileprivate func makeExportPayload(
    count: Int,
    startingTMDbID: Int = 10_000
) -> (
    entries: [LibraryEntrySyncDirtyQueueEntry],
    snapshots: [LibraryEntryIdentity: LibraryEntrySyncSnapshot],
    identities: [LibraryEntryIdentity]
) {
    var entries: [LibraryEntrySyncDirtyQueueEntry] = []
    var snapshots: [LibraryEntryIdentity: LibraryEntrySyncSnapshot] = [:]
    var identities: [LibraryEntryIdentity] = []

    for offset in 0..<count {
        let tmdbID = startingTMDbID + offset
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: tmdbID)
        entries.append(
            .upsert(.init(identity: identity, dirtyAt: referenceDate(year: 2026, month: 6, day: 12)))
        )
        snapshots[identity] = makeSnapshot(identity: identity, tmdbID: tmdbID)
        identities.append(identity)
    }

    return (entries, snapshots, identities)
}

fileprivate func makeSnapshot(
    identity: LibraryEntryIdentity,
    tmdbID: Int,
    entryType: AnimeType = .series,
    trackingUpdatedAt: Date? = referenceDate(year: 2026, month: 5, day: 1),
    notes: String = ""
) -> LibraryEntrySyncSnapshot {
    LibraryEntrySyncSnapshot(
        identity: identity,
        tmdbID: tmdbID,
        parentSeriesID: entryType.parentSeriesID,
        seasonNumber: entryType.seasonNumber,
        entryType: entryType,
        onDisplay: true,
        dateSaved: referenceDate(year: 2026, month: 5, day: 1),
        watchStatus: .planToWatch,
        dateStarted: nil,
        dateFinished: nil,
        isDateTrackingEnabled: true,
        score: nil,
        favorite: false,
        notes: notes,
        usingCustomPoster: false,
        customPosterPath: nil,
        episodeProgresses: [],
        libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: 1),
        trackingUpdatedAt: trackingUpdatedAt
    )
}

fileprivate func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}
