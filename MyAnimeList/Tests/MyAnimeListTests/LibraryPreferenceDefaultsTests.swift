//
//  LibraryPreferenceDefaultsTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibraryPreferenceDefaultsTests {
    @Test func testSingleTapDetailPreferenceDefaults() {
        let suiteName = "MyAnimeListTests.SingleTapDetailPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .libraryOpenDetailWithSingleTap) == nil)
        #expect(defaults.bool(forKey: .libraryOpenDetailWithSingleTap) == false)

        defaults.set(true, forKey: .libraryOpenDetailWithSingleTap)
        #expect(defaults.bool(forKey: .libraryOpenDetailWithSingleTap))
    }

    @Test func testEntryDetailExpansionPreferenceDefaults() {
        let suiteName = "MyAnimeListTests.EntryDetailExpansionPreferences"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .entryDetailCharactersExpandedByDefault) == nil)
        #expect(defaults.bool(forKey: .entryDetailCharactersExpandedByDefault) == false)
        #expect(defaults.object(forKey: .entryDetailStaffExpandedByDefault) == nil)
        #expect(defaults.bool(forKey: .entryDetailStaffExpandedByDefault) == false)

        defaults.set(false, forKey: .entryDetailCharactersExpandedByDefault)
        defaults.set(true, forKey: .entryDetailStaffExpandedByDefault)

        #expect(!defaults.bool(forKey: .entryDetailCharactersExpandedByDefault))
        #expect(defaults.bool(forKey: .entryDetailStaffExpandedByDefault))
    }

    @Test func testPosterProgressBarOverlayPreferenceDefaults() {
        let suiteName = "MyAnimeListTests.PosterProgressBarOverlayPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .libraryPosterProgressBarOverlayEnabled) == nil)
        #expect(defaults.bool(forKey: .libraryPosterProgressBarOverlayEnabled) == false)
        #expect(defaults.bool(forKey: .libraryPosterProgressBarOverlayEnabled, defaultValue: true))
        #expect(defaults.isLibraryPosterProgressBarOverlayEnabled)

        defaults.set(false, forKey: .libraryPosterProgressBarOverlayEnabled)

        #expect(!defaults.isLibraryPosterProgressBarOverlayEnabled)
    }

    @Test @MainActor func testLibraryGroupStrategyPreferenceRoundTrip() {
        let suiteName = "MyAnimeListTests.LibraryGroupStrategy"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LibraryPreferences(defaults: defaults)

        #expect(preferences.load().groupStrategy == .none)

        preferences.saveGroupStrategy(.score)
        #expect(preferences.load().groupStrategy == .score)

        defaults.set("invalid", forKey: .libraryGroupStrategy)
        #expect(preferences.load().groupStrategy == .none)
    }

    @Test @MainActor func testLongTermGalleryPosterCachingDefaultsOff() {
        let suiteName = "MyAnimeListTests.LongTermGalleryPosterCaching"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LibraryPreferences(defaults: defaults)

        #expect(defaults.object(forKey: .libraryLongTermGalleryPosterCachingEnabled) == nil)
        #expect(!preferences.load().longTermGalleryPosterCachingEnabled)
        #expect(!defaults.isLibraryLongTermGalleryPosterCachingEnabled)

        preferences.saveLongTermGalleryPosterCachingEnabled(true)

        #expect(preferences.load().longTermGalleryPosterCachingEnabled)
        #expect(defaults.isLibraryLongTermGalleryPosterCachingEnabled)
    }

    @Test @MainActor func testLibraryDefaultsPersistMultipleFiltersAndNewEntryStatus() throws {
        let defaults = UserDefaults.standard
        let keys = [
            String.libraryDefaultWatchStatus,
            String.libraryDefaultFilters,
            String.libraryDefaultFilterPreset,
            String.libraryAutoPrefetchImagesOnAddAndRestore
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })

        defer {
            for key in keys {
                if let value = originalValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(
            AnimeEntry.WatchStatus.watching.preferenceValue,
            forKey: .libraryDefaultWatchStatus
        )
        defaults.set(
            [
                LibraryStore.AnimeFilter.favorited.id,
                LibraryStore.AnimeFilter.watched.id
            ],
            forKey: .libraryDefaultFilters
        )
        defaults.removeObject(forKey: .libraryDefaultFilterPreset)
        defaults.set(false, forKey: .libraryAutoPrefetchImagesOnAddAndRestore)

        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))

        #expect(store.defaultFilters == Set([.favorited, .watched]))
        #expect(store.filters == Set([.favorited, .watched]))
        #expect(store.defaultNewEntryWatchStatus == .watching)

        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "Defaulted Entry",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 999_999,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        let entry = try #require(store.library.first(where: { $0.tmdbID == 999_999 }))
        #expect(entry.watchStatus == .watching)
    }

    @Test @MainActor func testApplyNewEntryDefaultsDoesNotStampTrackingClockForUntouchedTrackingState() {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 777)

        store.defaultNewEntryWatchStatus = .planToWatch
        store.applyNewEntryDefaults(to: entry)

        #expect(entry.watchStatus == .planToWatch)
        #expect(entry.libraryUpdatedAt != nil)
        #expect(entry.trackingUpdatedAt == nil)
    }

    @Test @MainActor func testApplyNewEntryDefaultsStampsTrackingClockWhenDefaultStatusChanges() {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 778)

        store.defaultNewEntryWatchStatus = .watching
        store.applyNewEntryDefaults(to: entry)

        #expect(entry.watchStatus == .watching)
        #expect(entry.libraryUpdatedAt != nil)
        #expect(entry.trackingUpdatedAt != nil)
    }
}
