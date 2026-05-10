//
//  LibraryPreferencesAndActionsTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibraryPreferencesAndActionsTests {
    @Test func testSingleTapDetailPreferenceDefaultsAndBackupInclusion() {
        let suiteName = "MyAnimeListTests.SingleTapDetailPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .libraryOpenDetailWithSingleTap) == nil)
        #expect(defaults.bool(forKey: .libraryOpenDetailWithSingleTap) == false)

        defaults.set(true, forKey: .libraryOpenDetailWithSingleTap)
        #expect(defaults.bool(forKey: .libraryOpenDetailWithSingleTap))

        #expect(String.allPreferenceKeys.contains(.libraryOpenDetailWithSingleTap))
    }

    @Test func testEntryDetailExpansionPreferenceDefaultsAndBackupInclusion() {
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
        #expect(String.allPreferenceKeys.contains(.entryDetailCharactersExpandedByDefault))
        #expect(String.allPreferenceKeys.contains(.entryDetailStaffExpandedByDefault))
    }

    @Test @MainActor func testLibraryGroupStrategyPreferenceRoundTripAndBackupInclusion() {
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

        #expect(String.allPreferenceKeys.contains(.libraryGroupStrategy))
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

        store.newEntryFromBasicInfo(
            BasicInfo(
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

    @Test @MainActor func testLibraryImageCacheCollectsRelatedDetailURLs() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://example.com/backdrop.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))
        let characterURL = try #require(URL(string: "https://example.com/character.jpg"))
        let staffURL = try #require(URL(string: "https://example.com/staff.jpg"))
        let seasonURL = try #require(URL(string: "https://example.com/season.jpg"))
        let episodeURL = try #require(URL(string: "https://example.com/episode.jpg"))

        let entry = AnimeEntry(
            name: "Cache Test",
            type: .series,
            posterURL: posterURL,
            backdropURL: backdropURL,
            tmdbID: 4
        )
        entry.detail = AnimeEntryDetail(
            language: "en",
            title: "Cache Test",
            heroImageURL: heroURL,
            logoImageURL: logoURL,
            characters: [
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Character",
                    actorName: "Actor",
                    profileURL: characterURL
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Director",
                    role: "Director",
                    profileURL: staffURL
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 2,
                    seasonNumber: 1,
                    title: "Season",
                    posterURL: seasonURL
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 3,
                    episodeNumber: 1,
                    title: "Episode",
                    imageURL: episodeURL
                )
            ]
        )

        let urls = LibraryImageCacheService.relatedImageURLs(for: entry)

        #expect(
            urls
                == Set([
                    posterURL,
                    backdropURL,
                    heroURL,
                    logoURL,
                    characterURL,
                    staffURL,
                    seasonURL,
                    episodeURL
                ])
        )
    }

    @Test @MainActor func testLibraryProfileSettingsActionsCreateBackupReturnsArchive() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let actions = LibraryProfileSettingsActions(store: store)

        let backupURL = try actions.createBackup()

        #expect(FileManager.default.fileExists(atPath: backupURL.path()))
    }

    @Test @MainActor func testLibraryProfileSettingsActionsClearLibraryRemovesEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.newEntryFromBasicInfo(
            BasicInfo(
                name: "Clear Me",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 100_001,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()
        #expect(store.library.count == 1)

        let actions = LibraryProfileSettingsActions(store: store)
        actions.clearLibrary()
        try store.refreshLibrary()

        #expect(store.library.isEmpty)
    }

    @Test @MainActor func testRefreshInfosIncludesSharedHiddenParentEntryOnce() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let parent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        parent.onDisplay = false

        let firstSeason = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209_867),
            tmdbID: 400_234
        )
        firstSeason.parentSeriesEntry = parent

        let secondSeason = AnimeEntry(
            name: "Season 2",
            type: .season(seasonNumber: 2, parentSeriesID: 209_867),
            tmdbID: 400_235
        )
        secondSeason.parentSeriesEntry = parent

        try store.repository.newEntry(parent)
        try store.repository.newEntry(firstSeason)
        try store.repository.newEntry(secondSeason)
        try store.refreshLibrary()

        #expect(store.library.count == 2)

        let capturedEntries = try LibraryProfileSettingsActions.getRefreshEntries(for: store)

        #expect(capturedEntries.count == 3)
        #expect(Set(capturedEntries.map(\.id)).count == 3)
        #expect(capturedEntries.filter { !$0.onDisplay && $0.tmdbID == 209_867 }.count == 1)
    }
}
