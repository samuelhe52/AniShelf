//
//  LibraryCloudSyncPreferencesTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

struct LibraryCloudSyncPreferencesTests {
    @Test @MainActor func testLibraryCloudSyncPreferenceDefaultsOff() {
        let suiteName = "MyAnimeListTests.LibraryCloudSyncPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LibraryPreferences(defaults: defaults)
        let status = preferences.load().cloudSyncStatus

        #expect(!status.isEnabled)
        #expect(status.bootstrapState == .notStarted)
    }

    @Test @MainActor func testLibraryCloudSyncPhasePersistsCoarseStatus() {
        let suiteName = "MyAnimeListTests.LibraryCloudSyncPhase"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LibraryPreferences(defaults: defaults)
        var status = LibraryCloudSyncStatus.defaultValue
        status.currentPhase = .remoteFetch

        preferences.saveCloudSyncStatus(status)

        #expect(defaults.string(forKey: .libraryCloudSyncCurrentPhase) == "syncing")
        #expect(preferences.load().cloudSyncStatus.currentPhase == .syncing)

        defaults.set("prepareZoneSubscription", forKey: .libraryCloudSyncCurrentPhase)
        #expect(preferences.load().cloudSyncStatus.currentPhase == .preparing)
    }

    @Test @MainActor func testPendingLocalSyncWorkIncludesUnsyncedCloudSettings() throws {
        let suiteName = "MyAnimeListTests.PendingCloudSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LibraryPreferences(defaults: defaults)
        let store = LibraryStore(
            dataProvider: DataProvider(inMemory: true),
            preferences: preferences
        )
        store.updateLibraryCloudSyncStatus { status in
            status.isEnabled = true
            status.bootstrapState = .completed
            status.lastSuccessfulSyncDate = Date(timeIntervalSince1970: 1_000)
            status.lastReconciledCloudSyncedSettingsUpdatedAt = Date(timeIntervalSince1970: 1_000)
        }
        preferences.saveSortReversed(false)
        preferences.saveCloudSyncedDefaultsUpdatedAt(Date(timeIntervalSince1970: 2_000))

        #expect(store.hasPendingCloudSyncedSettingsSyncWork())
        #expect(store.hasPendingLocalLibrarySyncWork())

        store.updateLibraryCloudSyncStatus { status in
            status.lastSuccessfulSyncDate = Date(timeIntervalSince1970: 3_000)
            status.lastReconciledCloudSyncedSettingsUpdatedAt = Date(timeIntervalSince1970: 3_000)
        }
        #expect(!store.hasPendingCloudSyncedSettingsSyncWork())
        #expect(!store.hasPendingLocalLibrarySyncWork())

        try store.syncChangeRecorder.dirtyQueueStore.setPendingUpsert(
            .init(
                identity: .init(entryType: .movie, tmdbID: 700_003),
                dirtyAt: Date(timeIntervalSince1970: 4_000)
            )
        )
        #expect(store.hasPendingLocalLibrarySyncWork())
    }

    @Test @MainActor func testCloudSyncedSettingsSnapshotExportsOnlyAllowlistedKeys() {
        let suiteName = "MyAnimeListTests.CloudSyncedSettingsSnapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("ja", forKey: .preferredAnimeInfoLanguage)
        defaults.set(false, forKey: .useCurrentLocaleForAnimeInfoLanguage)
        defaults.set("query", forKey: .searchPageQuery)
        defaults.set("grid", forKey: .libraryViewStyle)
        defaults.set("entry-1", forKey: .persistedScrolledID)
        defaults.set("series:42", forKey: .libraryLastInspectorDetailEntryIdentity)
        defaults.set("version-1", forKey: .lastSeenWhatsNewVersion)
        defaults.set(true, forKey: .libraryCloudSyncEnabled)
        defaults.set(true, forKey: .libraryLongTermGalleryPosterCachingEnabled)
        defaults.set(Data([0x01]), forKey: "CloudLibrarySyncToken.test")
        defaults.set(true, forKey: .useTMDbRelayServer)

        let preferences = LibraryPreferences(defaults: defaults)
        let snapshot = preferences.loadCloudSyncedSettingsSnapshot()

        #expect(snapshot.payload[.preferredAnimeInfoLanguage] == .string("ja"))
        #expect(snapshot.payload[.libraryViewStyle] == nil)
        #expect(snapshot.payload[.useTMDbRelayServer] == .bool(true))
        #expect(snapshot.payload[.searchPageQuery] == nil)
        #expect(snapshot.payload[.persistedScrolledID] == nil)
        #expect(snapshot.payload[.libraryLastInspectorDetailEntryIdentity] == nil)
        #expect(snapshot.payload[.lastSeenWhatsNewVersion] == nil)
        #expect(snapshot.payload[.libraryCloudSyncEnabled] == nil)
        #expect(snapshot.payload[.libraryLongTermGalleryPosterCachingEnabled] == nil)
        #expect(snapshot.payload["CloudLibrarySyncToken.test"] == nil)
    }
}
