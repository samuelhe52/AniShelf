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
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 901)
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
        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)

        importer.commit(batch)

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

        let identity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 902)
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
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 903)
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
        #expect(throws: CloudLibrarySyncDecodeError.unsupportedSchemaVersion(LibrarySettingsSyncSnapshot.currentSchemaVersion + 1)) {
            try client.settingsSnapshot(from: record)
        }
    }

    @Test func importerDecodesMixedEntryAndSettingsBatch() async throws {
        let namespace = makeNamespace()
        let suiteName = "CloudLibrarySyncImporterExporterTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let entryIdentity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 904)
        let entrySnapshot = makeSnapshot(identity: entryIdentity, tmdbID: 904, entryType: .movie)
        let settingsSnapshot = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: ["UseTMDbRelayServer": .bool(true)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
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
            successfulSaveRecordIDs: [client.recordID(for: first.syncIdentity)]
        )
        let exporter = CloudLibrarySyncExporter(client: client, database: database)

        let result = try await exporter.export(
            entries: [
                .upsert(.init(identity: first.syncIdentity, dirtyAt: referenceDate(year: 2026, month: 5, day: 8))),
                .delete(.init(tombstone: tombstone))
            ],
            localSnapshotsByIdentity: [first.syncIdentity: firstSnapshot]
        )

        #expect(result.exportedIdentities == [first.syncIdentity])
        #expect(database.savedRecords.count == 2)
        let savedTombstoneRecord = try #require(
            database.savedRecords.first { $0.recordID == client.recordID(for: second.syncIdentity) }
        )
        let savedTombstoneChange = try client.remoteChange(from: savedTombstoneRecord)
        #expect(savedTombstoneChange == .tombstone(tombstone))
        #expect(!savedTombstoneRecord.allKeys().contains("notes"))
        #expect(!savedTombstoneRecord.allKeys().contains("episodeProgresses"))
        #expect(!savedTombstoneRecord.allKeys().contains("watchStatus"))
    }

    @Test func exporterIncludesOptionalSettingsSnapshot() async throws {
        let identity = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 907)
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
}

fileprivate final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    private let firstFetchError: Error?
    private let successfulSaveRecordIDs: [CKRecord.ID]?
    private var didThrowFirstFetchError = false

    var requestedTokens: [CKServerChangeToken?] = []
    var savedRecords: [CKRecord] = []
    var ensureCallCount = 0

    init(
        changes: [CloudLibrarySyncZoneChangeBatch],
        firstFetchError: Error? = nil,
        successfulSaveRecordIDs: [CKRecord.ID]? = nil
    ) {
        self.changes = changes
        self.firstFetchError = firstFetchError
        self.successfulSaveRecordIDs = successfulSaveRecordIDs
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
        savedRecords.append(contentsOf: records)
        return successfulSaveRecordIDs ?? records.map(\.recordID)
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

fileprivate func makeSnapshot(
    identity: LibraryEntrySyncIdentity,
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
        customPosterURL: nil,
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
