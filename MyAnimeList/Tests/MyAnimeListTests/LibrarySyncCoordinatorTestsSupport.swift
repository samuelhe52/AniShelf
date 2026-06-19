//
//  LibrarySyncCoordinatorTestsSupport.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import CloudKit
import Foundation

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

enum HydrationFailure: Error {
    case unavailable
}

@MainActor
func makeSyncReadyStore() -> LibraryStore {
    makeStore(
        enabled: true,
        bootstrapState: .completed,
        hasTMDbAPIKey: true
    )
}

@MainActor
func makeStore(
    enabled: Bool,
    bootstrapState: LibraryCloudSyncBootstrapState,
    hasTMDbAPIKey: Bool
) -> LibraryStore {
    let suiteName = "LibrarySyncCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let preferences = LibraryPreferences(defaults: defaults)
    var status = LibraryCloudSyncStatus.defaultValue
    status.isEnabled = enabled
    status.bootstrapState = bootstrapState
    preferences.saveCloudSyncStatus(status)
    return LibraryStore(
        dataProvider: DataProvider(inMemory: true),
        preferences: preferences,
        hasTMDbAPIKey: { hasTMDbAPIKey }
    )
}

struct ClocklessTrackingConflictFixture {
    let store: LibraryStore
    let client: CloudLibrarySyncClient
    let database: FakeCloudLibrarySyncDatabase
    let identity: LibraryEntrySyncIdentity
}

@MainActor
func makeClocklessTrackingConflictFixture(
    repeatedRemoteFetches: Int = 1,
    dateProvider: @escaping @MainActor @Sendable () -> Date = {
        referenceDate(year: 2026, month: 6, day: 1)
    }
) throws -> ClocklessTrackingConflictFixture {
    let store = makeStore(
        enabled: false,
        bootstrapState: .notStarted,
        hasTMDbAPIKey: true
    )
    let entry = AnimeEntry(
        name: "Clockless Local",
        type: .series,
        tmdbID: 803,
        dateSaved: referenceDate(year: 2026, month: 5, day: 1)
    )
    entry.notes = "Local notes"
    entry.libraryUpdatedAt = nil
    entry.trackingUpdatedAt = nil
    try store.repository.newEntry(entry)
    try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
    store.rebuildSyncChangeTracking()

    let client = CloudLibrarySyncClient()
    var remoteSnapshot = makeSnapshot(
        identity: entry.syncIdentity,
        tmdbID: entry.tmdbID,
        notes: "Remote notes",
        trackingUpdatedAt: nil
    )
    remoteSnapshot.libraryUpdatedAt = nil
    let batch = try makeChangeBatch(client: client, snapshots: [remoteSnapshot])
    let database = FakeCloudLibrarySyncDatabase(
        changes: Array(repeating: batch, count: repeatedRemoteFetches)
    )
    store.configureLibrarySyncCoordinator(
        client: client,
        database: database,
        namespaceProvider: { makeNamespace() },
        dateProvider: dateProvider
    )
    return .init(
        store: store,
        client: client,
        database: database,
        identity: entry.syncIdentity
    )
}

final class FakeCloudLibrarySyncDatabase: CloudLibrarySyncDatabase, @unchecked Sendable {
    private var changes: [CloudLibrarySyncZoneChangeBatch]
    private let successfulSaveRecordIDs: [CKRecord.ID]?
    private let saveErrorsByCallIndex: [Int: any Error]
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var saveCallCount = 0
    var fetchedChangeTokens: [CKServerChangeToken?] = []
    var savedRecords: [CKRecord] = []
    var saveBatchSizes: [Int] = []
    var ensureZoneCallCount = 0
    var suspendNextFetch = false
    var suspendNextSave = false
    var suspendedFetchCount = 0
    var isFetchSuspended = false
    var isSaveSuspended = false

    init(
        changes: [CloudLibrarySyncZoneChangeBatch],
        successfulSaveRecordIDs: [CKRecord.ID]? = nil,
        saveErrorsByCallIndex: [Int: any Error] = [:]
    ) {
        self.changes = changes
        self.successfulSaveRecordIDs = successfulSaveRecordIDs
        self.saveErrorsByCallIndex = saveErrorsByCallIndex
    }

    func ensureZoneAndSubscription(
        zoneID: CKRecordZone.ID,
        subscriptionID: CKSubscription.ID
    ) async throws {
        ensureZoneCallCount += 1
    }

    func fetchRecordZoneChanges(
        in zoneID: CKRecordZone.ID,
        since changeToken: CKServerChangeToken?
    ) async throws -> CloudLibrarySyncZoneChangeBatch {
        fetchedChangeTokens.append(changeToken)
        if suspendNextFetch || suspendedFetchCount > 0 {
            if suspendNextFetch {
                suspendNextFetch = false
            }
            if suspendedFetchCount > 0 {
                suspendedFetchCount -= 1
            }
            isFetchSuspended = true
            await withCheckedContinuation { continuation in
                fetchContinuation = continuation
            }
            isFetchSuspended = false
        }
        return changes.removeFirst()
    }

    func save(records: [CKRecord]) async throws -> [CKRecord.ID] {
        saveCallCount += 1
        saveBatchSizes.append(records.count)
        if let error = saveErrorsByCallIndex[saveCallCount] {
            throw error
        }
        savedRecords.append(contentsOf: records)
        if suspendNextSave {
            suspendNextSave = false
            isSaveSuspended = true
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
            }
            isSaveSuspended = false
        }
        return successfulSaveRecordIDs ?? records.map(\.recordID)
    }

    func resumeSuspendedFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }

    func resumeSuspendedSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }
}

func makeNamespace() -> CloudLibrarySyncChangeTokenStore.Namespace {
    .init(
        containerIdentifier: CloudLibrarySyncClient.defaultContainerIdentifier,
        accountIdentifier: "test-account"
    )
}

func makeToken() -> CKServerChangeToken {
    class_createInstance(CKServerChangeToken.self, 0) as! CKServerChangeToken
}

func makeEmptyChangeBatch() -> CloudLibrarySyncZoneChangeBatch {
    .init(
        modifiedRecordsByID: [:],
        deletedRecordIDs: [],
        changeToken: makeToken(),
        moreComing: false
    )
}

struct RawDirtyQueue: Encodable {
    var schemaVersion: Int
    var entries: [LibraryEntrySyncDirtyQueueEntry]
}

@MainActor
func writeRawDirtyQueueEntries(
    _ entries: [LibraryEntrySyncDirtyQueueEntry],
    in store: LibraryStore
) throws {
    let queue = RawDirtyQueue(
        schemaVersion: LibraryEntrySyncDirtyQueue.currentSchemaVersion,
        entries: entries
    )
    let data = try JSONEncoder().encode(queue)
    try data.write(to: store.syncChangeRecorder.dirtyQueueStore.url)
}

func makeChangeBatch(
    client: CloudLibrarySyncClient,
    snapshots: [LibraryEntrySyncSnapshot]
) throws -> CloudLibrarySyncZoneChangeBatch {
    .init(
        modifiedRecordsByID: Dictionary(
            uniqueKeysWithValues: try snapshots.map { snapshot in
                (client.recordID(for: snapshot.identity), try client.record(from: snapshot))
            }
        ),
        deletedRecordIDs: [],
        changeToken: makeToken(),
        moreComing: false
    )
}

func savedSnapshot(
    from record: CKRecord,
    client: CloudLibrarySyncClient
) throws -> LibraryEntrySyncSnapshot {
    guard case .snapshot(let snapshot) = try client.remoteChange(from: record) else {
        throw SavedRecordError.expectedSnapshot
    }
    return snapshot
}

func makeSnapshot(
    identity: LibraryEntrySyncIdentity,
    tmdbID: Int,
    entryType: AnimeType = .series,
    notes: String = "",
    trackingUpdatedAt: Date? = referenceDate(year: 2026, month: 5, day: 1)
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

enum SavedRecordError: Error {
    case expectedSnapshot
}
