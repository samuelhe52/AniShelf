//
//  LibrarySyncCoordinatorTests+Settings.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import CloudKit
import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

extension LibrarySyncCoordinatorTests {
    @Test @MainActor func coalescedBootstrapDoesNotClearUnknownSettingsBlock() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        store.preferences.noteCloudSyncedSettingsTypes(
            .init(
                updatedAt: referenceDate(year: 2026, month: 6, day: 2),
                payload: [.useTMDbRelayServer: .unknown(.number(1))]
            ))
        let database = FakeCloudLibrarySyncDatabase(changes: [
            makeEmptyChangeBatch(), makeEmptyChangeBatch()
        ])
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: client, database: database,
            namespaceProvider: { makeNamespace() }
        )

        let ordinary = Task { await store.performLibrarySyncResult(trigger: .manualRetry) }
        while !database.isFetchSuspended { await Task.yield() }
        let bootstrap = Task { await store.bootstrapLibraryCloudSyncEnablementOutcome() }
        while store.libraryCloudSyncStatus.bootstrapState != .running { await Task.yield() }
        #expect(store.preferences.hasUnknownCloudSyncedSettingsValues)

        database.resumeSuspendedFetch()
        _ = await ordinary.value
        _ = await bootstrap.value
        #expect(store.preferences.hasUnknownCloudSyncedSettingsValues)
        #expect(!database.savedRecords.contains { $0.recordID == client.librarySettingsRecordID })
    }

    @Test @MainActor func explicitSyncResetsClearUnknownSettingsBlock() {
        let store = makeSyncReadyStore()
        let suiteName = "UnknownSettingsReset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: FakeCloudLibrarySyncDatabase(changes: []),
            changeTokenStore: CloudLibrarySyncChangeTokenStore(userDefaults: defaults),
            namespaceProvider: { makeNamespace() }
        )
        let unknown = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 2),
            payload: [.useTMDbRelayServer: .unknown(.number(1))]
        )

        store.preferences.noteCloudSyncedSettingsTypes(unknown)
        store.resetLibraryCloudSyncChangeTokens()
        #expect(!store.preferences.hasUnknownCloudSyncedSettingsValues)

        store.preferences.noteCloudSyncedSettingsTypes(unknown)
        store.resetLibraryCloudSyncAfterBackupRestore()
        #expect(!store.preferences.hasUnknownCloudSyncedSettingsValues)
    }

    @Test @MainActor func accountSwitchClearsOldUnknownSettingsBlockBeforeExport() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 1),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.preferences.noteCloudSyncedSettingsTypes(
            .init(
                updatedAt: referenceDate(year: 2026, month: 6, day: 2),
                payload: [.useTMDbRelayServer: .unknown(.number(1))]
            ))
        #expect(store.preferences.hasUnknownCloudSyncedSettingsValues)

        let newNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
            accountIdentifier: "new-settings-account"
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: client, database: database,
            namespaceProvider: { newNamespace }
        )

        #expect(await store.performLibrarySyncResult(trigger: .foreground) == .success)
        #expect(!store.preferences.hasUnknownCloudSyncedSettingsValues)
        #expect(database.savedRecords.contains { $0.recordID == client.librarySettingsRecordID })
    }

    @Test @MainActor func unknownRemoteSettingsKeepLocalValueAndBlockLaterExport() async throws {
        let store = makeSyncReadyStore()
        let original = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 1),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(original)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(original.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remote = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [
                .useTMDbRelayServer: .unknown(.number(1)),
                .preferredAnimeInfoLanguage: .string("ja")
            ]
        )
        let supported = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 3),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remote)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            ),
            makeEmptyChangeBatch(),
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: supported)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(store.preferences.loadCloudSyncedSettingsSnapshot().payload[.useTMDbRelayServer] == .bool(true))
        #expect(store.language == .japanese)
        #expect(store.preferences.hasUnknownCloudSyncedSettingsValues)

        store.preferences.saveCloudSyncedDefaultsUpdatedAt(referenceDate(year: 2026, month: 6, day: 6))
        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(database.savedRecords.allSatisfy { $0.recordID != client.librarySettingsRecordID })
        #expect(store.hasPendingCloudSyncedSettingsSyncWork())

        // A device whose clock is behind replaces the unknown values. The
        // current record is safe, so local settings export again.
        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(!store.preferences.hasUnknownCloudSyncedSettingsValues)
        #expect(database.savedRecords.contains { $0.recordID == client.librarySettingsRecordID })
        #expect(!store.hasPendingCloudSyncedSettingsSyncWork())
    }

    @Test @MainActor func newerRemoteSettingsApplyLocally() async throws {
        let store = makeSyncReadyStore()
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(referenceDate(year: 2026, month: 6, day: 1))
        store.preferences.applyCloudSyncedSettingsSnapshot(
            .init(
                updatedAt: referenceDate(year: 2026, month: 6, day: 1),
                payload: [.useTMDbRelayServer: .bool(false)]
            )
        )
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [
                .useTMDbRelayServer: .bool(true),
                .preferredAnimeInfoLanguage: .string("ja"),
                .useCurrentLocaleForAnimeInfoLanguage: .bool(false)
            ]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == remoteSettings.updatedAt)
        #expect(store.preferences.loadCloudSyncedSettingsSnapshot().payload[.useTMDbRelayServer] == .bool(true))
        #expect(store.language == .japanese)
    }

    @Test @MainActor func olderRemoteSettingsAreIgnored() async throws {
        let store = makeSyncReadyStore()
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 1),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == localSettings.updatedAt)
        #expect(store.preferences.loadCloudSyncedSettingsSnapshot().payload[.useTMDbRelayServer] == .bool(true))
    }

    @Test @MainActor func newerLocalSettingsExport() async throws {
        let store = makeSyncReadyStore()
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 1),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        let savedSettingsRecord = try #require(
            database.savedRecords.first { $0.recordID == client.librarySettingsRecordID }
        )
        #expect(try client.settingsSnapshot(from: savedSettingsRecord) == localSettings)
    }

    @Test @MainActor func settingsEditedDuringInFlightExportRemainPending() async throws {
        let store = makeSyncReadyStore()
        let originalSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(false)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(originalSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(originalSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [
            makeEmptyChangeBatch(),
            makeEmptyChangeBatch()
        ])
        database.suspendNextSave = true
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await coordinator.syncResult(trigger: .localChange)
        }
        for _ in 0..<50 where !database.isSaveSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(database.isSaveSuspended)

        let updatedSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 6),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(updatedSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(updatedSettings.updatedAt)
        store.reloadPersistedPreferences()

        database.resumeSuspendedSave()
        let firstResult = await syncTask.value

        #expect(firstResult == .success)
        var savedSettingsRecords = database.savedRecords.filter {
            $0.recordID == client.librarySettingsRecordID
        }
        #expect(savedSettingsRecords.count == 1)
        #expect(try client.settingsSnapshot(from: try #require(savedSettingsRecords.first)) == originalSettings)
        #expect(store.hasPendingCloudSyncedSettingsSyncWork())

        let followUpResult = await coordinator.syncResult(trigger: .localChange)

        #expect(followUpResult == .success)
        savedSettingsRecords = database.savedRecords.filter {
            $0.recordID == client.librarySettingsRecordID
        }
        #expect(savedSettingsRecords.count == 2)
        #expect(try client.settingsSnapshot(from: try #require(savedSettingsRecords.last)) == updatedSettings)
        #expect(!store.hasPendingCloudSyncedSettingsSyncWork())
    }

    @Test @MainActor func partialSettingsExportDoesNotAdvanceReconciledSettingsWatermark() async throws {
        let store = makeSyncReadyStore()
        let previousReconciledUpdatedAt = referenceDate(year: 2026, month: 6, day: 4)
        store.updateLibraryCloudSyncStatus { status in
            status.lastReconciledCloudSyncedSettingsUpdatedAt = previousReconciledUpdatedAt
        }
        let localSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        store.preferences.applyCloudSyncedSettingsSnapshot(localSettings)
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(localSettings.updatedAt)
        store.reloadPersistedPreferences()

        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(
            changes: [makeEmptyChangeBatch()],
            successfulSaveRecordIDs: []
        )
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.libraryCloudSyncStatus.rejectedUploadCount == 1)
        #expect(database.savedRecords.count == 1)
        #expect(
            store.libraryCloudSyncStatus.lastReconciledCloudSyncedSettingsUpdatedAt
                == previousReconciledUpdatedAt
        )
        #expect(store.hasPendingCloudSyncedSettingsSyncWork())
    }

    @Test @MainActor func remoteSettingsApplyDoesNotRestampLocalClockAsFreshEdit() async throws {
        let store = makeSyncReadyStore()
        store.preferences.saveCloudSyncedDefaultsUpdatedAt(referenceDate(year: 2026, month: 6, day: 1))
        let client = CloudLibrarySyncClient()
        let remoteSettings = LibrarySettingsSyncSnapshot(
            updatedAt: referenceDate(year: 2026, month: 6, day: 5),
            payload: [.useTMDbRelayServer: .bool(true)]
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.librarySettingsRecordID: try client.record(from: remoteSettings)],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            )
        ])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: client,
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .success)
        #expect(store.preferences.cloudSyncedDefaultsUpdatedAt() == remoteSettings.updatedAt)
        #expect(
            store.libraryCloudSyncStatus.lastReconciledCloudSyncedSettingsUpdatedAt
                == remoteSettings.updatedAt
        )
        #expect(!store.hasPendingCloudSyncedSettingsSyncWork())
        let savedSettingsRecords = database.savedRecords.filter { $0.recordID == client.librarySettingsRecordID }
        #expect(savedSettingsRecords.isEmpty)
    }
}
