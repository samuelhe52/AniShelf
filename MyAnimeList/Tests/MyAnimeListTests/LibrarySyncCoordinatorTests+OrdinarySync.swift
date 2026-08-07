//
//  LibrarySyncCoordinatorTests+OrdinarySync.swift
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

@MainActor
fileprivate final class TestTMDbAPIKeyAvailability {
    var isAvailable = false
}

extension LibrarySyncCoordinatorTests {
    @Test @MainActor func ordinarySyncSkipsWhenCloudSyncDisabled() async throws {
        let store = makeStore(
            enabled: false,
            bootstrapState: .completed,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.disabled))
        #expect(database.ensureZoneCallCount == 0)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
    }

    @Test @MainActor func ordinarySyncSkipsWhenTMDbAPIKeyIsMissing() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .completed,
            hasTMDbAPIKey: false
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.missingTMDbAPIKey))
        #expect(database.ensureZoneCallCount == 0)
    }

    @Test @MainActor func ordinarySyncSkipsWhenBootstrapIsIncomplete() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .needsConflictChoice,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [])
        let coordinator = LibrarySyncCoordinator(
            store: store,
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await coordinator.syncResult(trigger: .manualRetry)

        #expect(result == .skipped(.bootstrapIncomplete))
        #expect(database.ensureZoneCallCount == 0)
    }

    @Test @MainActor func appLaunchResumesInterruptedFirstEnableBootstrap() async throws {
        let store = makeStore(
            enabled: true,
            bootstrapState: .running,
            hasTMDbAPIKey: true
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let result = await store.performLibrarySyncResult(trigger: .appLaunch)

        #expect(result == .success)
        #expect(store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastResult == .success)
        #expect(database.ensureZoneCallCount == 1)
    }

    @Test @MainActor func appLaunchWaitsForAPIKeyThenBootstrapsDefaultEnabledCloudSync()
        async throws
    {
        let suiteName = "LibrarySyncCoordinatorTests.DefaultEnabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let apiKeyAvailability = TestTMDbAPIKeyAvailability()
        let store = LibraryStore(
            dataProvider: DataProvider(inMemory: true),
            preferences: LibraryPreferences(defaults: defaults),
            hasTMDbAPIKey: { apiKeyAvailability.isAvailable }
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let missingKeyResult = await store.performLibrarySyncResult(trigger: .appLaunch)

        #expect(missingKeyResult == .skipped(.missingTMDbAPIKey))
        #expect(store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(database.ensureZoneCallCount == 0)

        apiKeyAvailability.isAvailable = true
        let bootstrapResult = await store.performLibrarySyncResult(trigger: .foreground)

        #expect(bootstrapResult == .success)
        #expect(store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(database.ensureZoneCallCount == 1)
    }

    @Test @MainActor func manualRetryClearsDegradedStateAfterSuccessfulSync() async throws {
        let store = makeSyncReadyStore()
        store.updateLibraryCloudSyncStatus { status in
            status.retryState = .init(
                failureRetryAttempt: 4,
                nextRetryAllowedAt: referenceDate(year: 2026, month: 6, day: 2),
                automaticRetriesExhausted: true
            )
            status.degradedReason = "Automatic retries were exhausted."
        }
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let succeeded = await store.retryLibraryCloudSync()

        #expect(succeeded)
        #expect(store.libraryCloudSyncStatus.retryState == .idle)
        #expect(store.libraryCloudSyncStatus.degradedReason == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .success)
    }

    @Test @MainActor func disablingLibraryCloudSyncCancelsInFlightOrdinarySyncBeforeExport()
        async throws
    {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Cancelable Ordinary",
            type: .movie,
            tmdbID: 854,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(
                .init(
                    identity: entry.syncIdentity,
                    dirtyAt: referenceDate(year: 2026, month: 5, day: 2)
                ))
        ])

        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { makeNamespace() }
        )

        let syncTask = Task {
            await store.performLibrarySyncResult(trigger: .foreground)
        }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        store.disableLibraryCloudSync()
        database.resumeSuspendedFetch()
        let result = await syncTask.value

        #expect(result == .skipped(.disabled))
        #expect(!store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .notStarted)
        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == .skipped)
        #expect(database.savedRecords.isEmpty)
    }
}
