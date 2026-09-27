//
//  LibrarySyncCoordinatorTests+OrdinarySync.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import CloudKit
import Foundation
import Testing
import TMDb

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
    @Test(arguments: [false, true])
    @MainActor func permanentReconstructionFailureCanBeDiscardedWithoutRetries(accountChanged: Bool) async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: 2399)
        let snapshot = makeSnapshot(identity: identity, tmdbID: 2399)
        // A retryable failure alongside must not block the discard.
        let retryableIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 2398)
        let retryableSnapshot = makeSnapshot(identity: retryableIdentity, tmdbID: 2398)
        let database = FakeCloudLibrarySyncDatabase(
            changes: [try makeChangeBatch(client: client, snapshots: [snapshot, retryableSnapshot])]
                + Array(repeating: makeEmptyChangeBatch(), count: 4)
        )
        var namespace = makeNamespace()
        var hydrationCount = 0
        store.configureLibrarySyncCoordinator(
            client: client, database: database, namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, _ in
                guard snapshot.identity == identity else { throw HydrationFailure.unavailable }
                hydrationCount += 1
                throw TMDbError.notFound(TMDbErrorContext(statusMessage: "Not found"))
            }
        )

        // A permanent failure neither degrades sync nor retries on automatic passes.
        #expect(await store.performLibrarySync(trigger: .localChange))
        #expect(await store.performLibrarySync(trigger: .foreground))
        #expect(hydrationCount == 1)
        #expect(store.libraryCloudSyncStatus.lastSuccessfulSyncDate != nil)
        let failure = try #require(
            store.libraryCloudSyncStatus.currentPendingReconstructionFailures.first { $0.snapshot.identity == identity }
        )
        #expect(failure.canDiscard)

        if accountChanged {
            namespace = .init(
                containerIdentifier: namespace.containerIdentifier, accountIdentifier: "different-account")
        }
        let discarded = await store.discardFailedPendingReconstruction(failure)
        #expect(hydrationCount == 1)
        if accountChanged {
            #expect(database.savedRecords.isEmpty)
        } else {
            #expect(discarded)
            #expect(database.savedRecords.count == 1)
            guard case .tombstone(let deletion) = try client.remoteChange(from: #require(database.savedRecords.first))
            else {
                Issue.record("Expected only the discarded entry's deletion")
                return
            }
            #expect(deletion.identity == identity)
            #expect(deletion.deletedAt > (snapshot.latestUserStateClock ?? .distantPast))
            #expect(
                store.libraryCloudSyncStatus.currentPendingReconstructionFailures.map(\.snapshot.identity)
                    == [retryableIdentity])
        }
    }

    @Test @MainActor func unreadableRecordDoesNotBlockOtherUploadsOrLosePendingWork() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let bad = AnimeEntry(name: "Unreadable remote", type: .series, tmdbID: 2201)
        let good = AnimeEntry(name: "Independent local", type: .series, tmdbID: 2202)
        try store.repository.newEntry(bad)
        try store.repository.newEntry(good)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(.init(identity: bad.libraryIdentity, dirtyAt: .now)),
            .upsert(.init(identity: good.libraryIdentity, dirtyAt: .now))
        ])
        store.rebuildSyncChangeTracking()
        let badRecord = try client.record(from: LibraryEntrySyncSnapshot(entry: bad))
        badRecord["schemaVersion"] = LibraryEntrySyncSnapshot.currentSchemaVersion + 1
        let database = FakeCloudLibrarySyncDatabase(changes: [
            .init(
                modifiedRecordsByID: [client.recordID(for: bad.libraryIdentity): badRecord],
                deletedRecordIDs: [],
                changeToken: makeToken(),
                moreComing: false
            ),
            makeEmptyChangeBatch()
        ])
        let quarantineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordinatorQuarantine.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: quarantineURL) }
        let quarantineStore = CloudLibrarySyncQuarantineStore(url: quarantineURL)
        let coordinator = LibrarySyncCoordinator(
            store: store, client: client, database: database,
            quarantineStore: quarantineStore,
            namespaceProvider: { makeNamespace() }
        )

        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(store.libraryCloudSyncStatus.quarantinedRecordCount == 1)
        #expect(database.savedRecords.contains { $0.recordID == client.recordID(for: good.libraryIdentity) })
        #expect(!database.savedRecords.contains { $0.recordID == client.recordID(for: bad.libraryIdentity) })
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: bad.libraryIdentity) != nil)

        #expect(await coordinator.syncResult(trigger: .manualRetry) == .success)
        #expect(store.libraryCloudSyncStatus.quarantinedRecordCount == 1)
        #expect(!database.savedRecords.contains { $0.recordID == client.recordID(for: bad.libraryIdentity) })
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: bad.libraryIdentity) != nil)
    }

    @Test @MainActor func failedOrdinaryHydrationReplaysAfterTokenCommitAndRelaunch() async throws {
        let store = makeSyncReadyStore()
        let client = CloudLibrarySyncClient()
        let recoveredIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 2301)
        let locallyCreatedIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: 2302)
        let independent = AnimeEntry(name: "Local upload", type: .series, tmdbID: 2303)
        independent.updateNotes("Still uploads", at: referenceDate(year: 2026, month: 5, day: 4))
        try store.repository.newEntry(independent)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .upsert(.init(identity: independent.libraryIdentity, dirtyAt: independent.trackingUpdatedAt ?? .now))
        ])
        store.rebuildSyncChangeTracking()
        let recovered = makeSnapshot(identity: recoveredIdentity, tmdbID: 2301, notes: "Remote one")
        let locallyCreated = makeSnapshot(identity: locallyCreatedIdentity, tmdbID: 2302, notes: "Remote two")
        let database = FakeCloudLibrarySyncDatabase(changes: [
            try makeChangeBatch(client: client, snapshots: [recovered, locallyCreated]),
            makeEmptyChangeBatch()
        ])
        let suiteName = "OrdinaryHydrationToken.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokens = CloudLibrarySyncChangeTokenStore(userDefaults: defaults)
        let initial = LibrarySyncCoordinator(
            store: store, client: client, database: database, changeTokenStore: tokens,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { _, _ in throw HydrationFailure.unavailable }
        )

        // Failed reconstructions stay pending without failing the pass.
        #expect(await initial.syncResult(trigger: .manualRetry) == .success)
        #expect(store.hasPendingLibrarySyncItemRetryWork())
        #expect(database.savedRecords.contains { $0.recordID == client.recordID(for: independent.libraryIdentity) })
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entry(for: independent.libraryIdentity) == nil)
        #expect(tokens.token(for: CloudLibrarySyncClient.recordZoneID, namespace: makeNamespace()) != nil)
        #expect(store.libraryCloudSyncStatus.pendingReconstructions.first?.failures.count == 2)
        #expect(store.preferences.load().cloudSyncStatus.pendingReconstructions.first?.failures.count == 2)

        let resumed = LibraryStore(
            dataProvider: store.dataProvider,
            preferences: store.preferences,
            hasTMDbAPIKey: { true }
        )
        let created = AnimeEntry(
            name: "Added after failed hydration", type: .series, tmdbID: 2302,
            dateSaved: referenceDate(year: 2026, month: 5, day: 2)
        )
        created.updateNotes("New local notes", at: referenceDate(year: 2026, month: 5, day: 2))
        try resumed.repository.newEntry(created)
        let retry = LibrarySyncCoordinator(
            store: resumed, client: client, database: database, changeTokenStore: tokens,
            namespaceProvider: { makeNamespace() },
            hydrateMissingEntry: { snapshot, _ in
                #expect(snapshot.identity == recoveredIdentity)
                return AnimeEntry(name: "Recovered", type: .series, tmdbID: snapshot.tmdbID)
            }
        )

        #expect(await retry.syncResult(trigger: .manualRetry) == .success)
        #expect(resumed.repository.existingEntry(identity: recoveredIdentity)?.notes == "Remote one")
        #expect(resumed.repository.existingEntry(identity: locallyCreatedIdentity)?.notes == "New local notes")
        #expect(resumed.libraryCloudSyncStatus.pendingReconstructions.isEmpty)
    }

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
