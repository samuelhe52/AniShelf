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

@MainActor
fileprivate final class SuspendedFirstNamespaceResolution {
    let namespace: CloudLibrarySyncChangeTokenStore.Namespace
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isSuspended = false
    private var resolutionCount = 0

    init(namespace: CloudLibrarySyncChangeTokenStore.Namespace) {
        self.namespace = namespace
    }

    func resolve() async -> CloudLibrarySyncChangeTokenStore.Namespace {
        resolutionCount += 1
        if resolutionCount == 1 {
            isSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
            isSuspended = false
        }
        return namespace
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
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

    @Test @MainActor func legacyCompletedStateAdoptsCurrentScopeWhenItsTokenExists() async throws {
        let store = makeSyncReadyStore()
        store.updateLibraryCloudSyncStatus { status in
            status.lastCompletedScope = nil
        }
        let namespace = makeNamespace()
        let tokenDefaults = UserDefaults(
            suiteName: "LibrarySyncCoordinatorTests.LegacyScope.\(UUID().uuidString)"
        )!
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: tokenDefaults)
        tokenStore.setToken(
            makeToken(),
            for: CloudLibrarySyncClient.recordZoneID,
            namespace: namespace
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace }
        )

        let result = await store.performLibrarySyncResult(trigger: .appLaunch)

        #expect(result == .success)
        #expect(database.fetchedChangeTokens.count == 1)
        #expect(database.fetchedChangeTokens[0] != nil)
        #expect(store.libraryCloudSyncStatus.lastCompletedScope == makeSyncScope(namespace: namespace))
    }

    @Test @MainActor func accountChangeRunsFullBootstrapAndRepublishesCleanLocalLibrary() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Account Switch Local",
            type: .movie,
            tmdbID: 855,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let newNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
            accountIdentifier: "other-account"
        )
        let tokenDefaults = UserDefaults(
            suiteName: "LibrarySyncCoordinatorTests.AccountChange.\(UUID().uuidString)"
        )!
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: tokenDefaults)
        tokenStore.setToken(
            makeToken(),
            for: CloudLibrarySyncClient.recordZoneID,
            namespace: newNamespace
        )
        let client = CloudLibrarySyncClient()
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { newNamespace }
        )

        let result = await store.performLibrarySyncResult(trigger: .foreground)

        #expect(result == .success)
        #expect(database.fetchedChangeTokens.count == 1)
        #expect(database.fetchedChangeTokens[0] == nil)
        #expect(database.savedRecords.contains { $0.recordID == client.recordID(for: entry.libraryIdentity) })
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastCompletedScope == makeSyncScope(namespace: newNamespace))
    }

    @Test @MainActor func accountChangingDuringScopeCheckStopsOrdinaryRemoteFetch() async throws {
        let store = makeSyncReadyStore()
        let originalNamespace = makeNamespace()
        let changedNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
            accountIdentifier: "changed-during-sync"
        )
        var namespaces = [originalNamespace, changedNamespace]
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { namespaces.removeFirst() }
        )

        let result = await store.performLibrarySyncResult(trigger: .foreground)

        #expect(result == .retryableFailure)
        #expect(database.fetchedChangeTokens.isEmpty)
        #expect(store.libraryCloudSyncStatus.lastCompletedScope == makeSyncScope(namespace: originalNamespace))
    }

    @Test @MainActor func syncStartingDuringScopeResolutionCoalescesWithRunningPass() async throws {
        let store = makeSyncReadyStore()
        let namespaceResolution = SuspendedFirstNamespaceResolution(namespace: makeNamespace())
        let database = FakeCloudLibrarySyncDatabase(
            changes: [makeEmptyChangeBatch(), makeEmptyChangeBatch()]
        )
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { await namespaceResolution.resolve() }
        )

        let firstSync = Task {
            await store.performLibrarySyncResult(trigger: .foreground)
        }
        while !namespaceResolution.isSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let secondSync = Task {
            await store.performLibrarySyncResult(trigger: .cloudNotification)
        }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        namespaceResolution.resume()
        while namespaceResolution.isSuspended {
            await Task.yield()
        }
        await Task.yield()
        database.resumeSuspendedFetch()

        let firstResult = await firstSync.value
        let secondResult = await secondSync.value

        #expect(firstResult == .success)
        #expect(secondResult == .success)
        #expect(database.ensureZoneCallCount == 2)
        #expect(database.fetchedChangeTokens.count == 2)
    }

    @Test @MainActor func backgroundProtectionIncludesNamespaceResolution() async throws {
        let store = makeSyncReadyStore()
        let namespaceResolution = SuspendedFirstNamespaceResolution(namespace: makeNamespace())
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            namespaceProvider: { await namespaceResolution.resolve() }
        )

        #expect(!store.needsBackgroundLibrarySyncProtection)

        let syncTask = Task {
            await store.performLibrarySyncResult(trigger: .foreground)
        }
        while !namespaceResolution.isSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.needsBackgroundLibrarySyncProtection)

        namespaceResolution.resume()
        let result = await syncTask.value

        #expect(result == .success)
        #expect(!store.needsBackgroundLibrarySyncProtection)
    }

    @Test @MainActor func manualRebuildClearsScopeAndTokenWithoutClearingDirtyQueue() async throws {
        let store = makeSyncReadyStore()
        let entry = AnimeEntry(
            name: "Manual Rebuild Local",
            type: .series,
            tmdbID: 856,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try store.repository.newEntry(entry)
        let dirtyEntry = LibraryEntrySyncDirtyQueueEntry.upsert(
            .init(
                identity: entry.libraryIdentity,
                dirtyAt: referenceDate(year: 2026, month: 5, day: 2)
            )
        )
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([dirtyEntry])

        let namespace = makeNamespace()
        let tokenDefaults = UserDefaults(
            suiteName: "LibrarySyncCoordinatorTests.ManualRebuild.\(UUID().uuidString)"
        )!
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: tokenDefaults)
        tokenStore.setToken(
            makeToken(),
            for: CloudLibrarySyncClient.recordZoneID,
            namespace: namespace
        )
        let database = FakeCloudLibrarySyncDatabase(changes: [makeEmptyChangeBatch()])
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace }
        )

        let rebuildTask = Task { await store.rebuildLibraryCloudSync() }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) == nil)
        #expect(store.libraryCloudSyncStatus.lastCompletedScope == nil)
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries == [dirtyEntry])
        #expect(store.library.contains { $0.libraryIdentity == entry.libraryIdentity })

        database.resumeSuspendedFetch()
        let rebuilt = await rebuildTask.value
        #expect(rebuilt)
        #expect(store.libraryCloudSyncStatus.lastCompletedScope == makeSyncScope(namespace: namespace))
    }

    @Test @MainActor func manualRebuildWaitsForCanceledOrdinarySyncBeforeBootstrapping() async throws {
        let store = makeSyncReadyStore()
        let namespace = makeNamespace()
        let tokenDefaults = UserDefaults(
            suiteName: "LibrarySyncCoordinatorTests.InFlightManualRebuild.\(UUID().uuidString)"
        )!
        let tokenStore = CloudLibrarySyncChangeTokenStore(userDefaults: tokenDefaults)
        tokenStore.setToken(
            makeToken(),
            for: CloudLibrarySyncClient.recordZoneID,
            namespace: namespace
        )
        let database = FakeCloudLibrarySyncDatabase(
            changes: [makeEmptyChangeBatch(), makeEmptyChangeBatch()]
        )
        database.suspendNextFetch = true
        store.configureLibrarySyncCoordinator(
            client: CloudLibrarySyncClient(),
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace }
        )

        let ordinarySyncTask = Task {
            await store.performLibrarySyncResult(trigger: .foreground)
        }
        while !database.isFetchSuspended {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        var rebuildStarted = false
        let rebuildTask = Task {
            rebuildStarted = true
            return await store.rebuildLibraryCloudSync()
        }
        while !rebuildStarted {
            await Task.yield()
        }

        #expect(tokenStore.token(for: CloudLibrarySyncClient.recordZoneID, namespace: namespace) != nil)
        #expect(database.fetchedChangeTokens.count == 1)

        database.resumeSuspendedFetch()
        _ = await ordinarySyncTask.value
        let rebuilt = await rebuildTask.value

        #expect(rebuilt)
        #expect(database.fetchedChangeTokens.count == 2)
        #expect(database.fetchedChangeTokens[0] != nil)
        #expect(database.fetchedChangeTokens[1] == nil)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.lastCompletedScope == makeSyncScope(namespace: namespace))
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
                    identity: entry.libraryIdentity,
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

    @Test @MainActor func backgroundExpirationClearsInFlightOrdinarySyncStatus() async throws {
        let store = makeSyncReadyStore()
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

        #expect(store.libraryCloudSyncStatus.currentPhase == .syncing)
        store.cancelLibrarySyncForBackgroundExpiration()

        #expect(store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == nil)
        #expect(!store.libraryCloudSyncStatus.isSyncInProgress)

        database.resumeSuspendedFetch()
        let result = await syncTask.value

        #expect(result == .success)
        #expect(store.libraryCloudSyncStatus.currentPhase == nil)
        #expect(store.libraryCloudSyncStatus.lastResult == nil)
    }
}
