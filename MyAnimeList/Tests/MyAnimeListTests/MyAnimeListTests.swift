//
//  MyAnimeListTests.swift
//  MyAnimeListTests
//
//  Created by Samuel He on 2024/12/8.
//

import Foundation
import SwiftData
import Testing
import ZIPFoundation

@testable import DataProvider
@testable import MyAnimeList

struct MyAnimeListTests {
    let fetcher = InfoFetcher()
    let language: Language = .japanese
    @MainActor let dataProviderForPreview = DataProvider.forPreview
    @MainActor let backupManager = BackupManager(dataProvider: .forPreview)

    @Test func testFetchInfo() async throws {
        let result = try await fetcher.searchTVSeries(name: "Frieren", language: language).first
        try #require(result != nil, "No search results for 'Frieren'")
        let series = try await fetcher.tmdbClient.tvSeries
            .details(forTVSeries: result!.id, language: language.rawValue)
        let info = try await series.basicInfo(client: fetcher.tmdbClient)
        let entry = AnimeEntry(fromInfo: info)
        #expect(!entry.name.isEmpty)
    }

    @Test func testImageFetch() async throws {
        let result = try await fetcher.searchTVSeries(name: "CLANNAD", language: language).first
        try #require(result != nil, "No search results for 'CLANNAD'")
        let images = try await fetcher.tmdbClient.tvSeries.images(forTVSeries: result!.id)
        let jaPosters = images.posters.filter { $0.languageCode == "ja" }
        #expect(!jaPosters.isEmpty, "Expected at least one Japanese poster")
    }

    @Test func testBackdropPrefersNoLanguageForSeries() async throws {
        let seriesID = 209867  // Sousou no Frieren
        let series = try await fetcher.tmdbClient.tvSeries
            .details(forTVSeries: seriesID, language: language.rawValue)
        let images = try await fetcher.tmdbClient.tvSeries.images(forTVSeries: seriesID)
        let expectedPath = try #require(
            images.backdrops.first(where: { $0.languageCode == nil })?.filePath,
            "Expected at least one no-language backdrop"
        )
        let expectedURL = try await fetcher.tmdbClient.imagesConfiguration.backdropURL(
            for: expectedPath,
            idealWidth: 1_280
        )
        let actualURL = try await series.backdropURL(client: fetcher.tmdbClient, idealWidth: 1_280)
        #expect(actualURL == expectedURL)
    }

    @Test @MainActor func testBackup() throws {
        let backupURL = try backupManager.createBackup()
        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: backupURL.path()))
        let attributes = try fileManager.attributesOfItem(atPath: backupURL.path())
        let size = attributes[.size] as? NSNumber
        #expect(size != nil && size!.intValue > 0, "Backup file should not be empty")

        // Verify the backup is a valid ZIP
        let parentDirectoryURL = backupURL.deletingLastPathComponent()
        try fileManager.unzipItem(at: backupURL, to: parentDirectoryURL)
    }

    @Test @MainActor func testParentChildRelationshipInference() async throws {
        let dataProvider = dataProviderForPreview
        let parent = AnimeEntry.frieren
        let season = AnimeEntry(
            name: "Sousou no Frieren: Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: parent.tmdbID),
            tmdbID: 400234
        )
        season.parentSeriesEntry = parent
        #expect(parent.parentSeriesEntry == nil, "Parent should not have a parent before insertion")
        try dataProvider.dataHandler.newEntry(season)
    }

    @Test func testLibraryProfileStatsEmptyLibrary() {
        let stats = LibraryProfileStats(entries: [])

        #expect(stats.totalCount == 0)
        #expect(stats.favoriteCount == 0)
        #expect(stats.runtimeMinutes == 0)
    }

    @Test func testStableStaffIdentifierUsesCreditID() {
        let first = InfoFetcher.stableStaffIdentifier(
            creditID: "52fe4250c3a36847f8014a11",
            fallbackID: 7
        )
        let second = InfoFetcher.stableStaffIdentifier(
            creditID: "52fe4250c3a36847f8014a11",
            fallbackID: 99
        )
        let different = InfoFetcher.stableStaffIdentifier(
            creditID: "56380f0cc3a3681b5c0200be",
            fallbackID: 7
        )

        #expect(first == second)
        #expect(first != different)
    }

    @Test func testLibraryProfileStatsMixedLibrary() {
        let movie = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 1,
            detail: AnimeEntryDetail(language: "en", title: "Movie", runtimeMinutes: 100),
            dateSaved: referenceDate(year: 2026, month: 1, day: 3)
        )
        movie.setWatchStatus(.watched, now: referenceDate(year: 2026, month: 1, day: 3))
        movie.favorite = true
        movie.notes = "Worth rewatching"
        movie.usingCustomPoster = true

        let series = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 2,
            detail: AnimeEntryDetail(
                language: "en",
                title: "Series",
                runtimeMinutes: 24,
                episodeCount: 12
            ),
            dateSaved: referenceDate(year: 2026, month: 2, day: 8)
        )
        series.setWatchStatus(.watching, now: referenceDate(year: 2026, month: 2, day: 8))

        let season = AnimeEntry(
            name: "Season",
            type: .season(seasonNumber: 1, parentSeriesID: 2),
            tmdbID: 3
        )
        season.setWatchStatus(.dropped, now: referenceDate(year: 2026, month: 2, day: 8))

        let stats = LibraryProfileStats(entries: [movie, series, season])

        #expect(stats.totalCount == 3)
        #expect(stats.watchedCount == 1)
        #expect(stats.watchingCount == 1)
        #expect(stats.planToWatchCount == 0)
        #expect(stats.droppedCount == 1)
        #expect(stats.favoriteCount == 1)
        #expect(stats.movieCount == 1)
        #expect(stats.seriesCount == 1)
        #expect(stats.seasonCount == 1)
        #expect(stats.entriesWithNotesCount == 1)
        #expect(stats.runtimeMinutes == 388)
    }

    @Test func testEntryDetailLargeSeriesExpansionPolicy() {
        #expect(
            EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: 200,
                seasonCount: 1,
                seasonCardCount: 1
            )
        )
        #expect(
            !EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: 199,
                seasonCount: 20,
                seasonCardCount: 20
            )
        )
        #expect(
            EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: nil,
                seasonCount: 9,
                seasonCardCount: 0
            )
        )
        #expect(
            !EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: nil,
                seasonCount: nil,
                seasonCardCount: 8
            )
        )
    }

    @Test @MainActor func testEntryDetailPlacesSpecialsSeasonAfterNumberedSeasons() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let viewModel = EntryDetailViewModel(repository: repository)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 20,
            detail: AnimeEntryDetail(
                language: "en",
                title: "Series",
                logoImageURL: URL(string: "https://example.com/logo.png"),
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 100,
                        seasonNumber: 0,
                        title: "Specials"
                    ),
                    AnimeEntrySeasonSummary(
                        id: 101,
                        seasonNumber: 2,
                        title: "Season 2"
                    ),
                    AnimeEntrySeasonSummary(
                        id: 102,
                        seasonNumber: 1,
                        title: "Season 1"
                    )
                ]
            )
        )

        await viewModel.load(for: entry, language: .english, dataHandler: nil)

        #expect(viewModel.seasonCards.map(\.seasonNumber) == [1, 2, 0])
    }

    @Test @MainActor func testEntryDetailLocalizesStaffRoleFallbacks() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))

        let japaneseViewModel = EntryDetailViewModel(repository: repository)
        let japaneseEntry = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 30,
            detail: AnimeEntryDetail(
                language: Language.japanese.rawValue,
                title: "Movie",
                logoImageURL: URL(string: "https://example.com/logo-ja.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 1,
                        name: "Staff One",
                        role: "Key Animation / Director"
                    ),
                    AnimeEntryStaff(
                        id: 2,
                        name: "Staff Two",
                        role: "Unknown Role"
                    ),
                    AnimeEntryStaff(
                        id: 5,
                        name: "Staff Five",
                        role: "Storyboard Artist / Settings"
                    )
                ]
            )
        )

        await japaneseViewModel.load(for: japaneseEntry, language: .japanese, dataHandler: nil)

        #expect(
            japaneseViewModel.staffCards.map(\.secondaryText)
                == ["原画 / 監督", "Unknown Role", "絵コンテ / 設定"]
        )

        let chineseViewModel = EntryDetailViewModel(repository: repository)
        let chineseEntry = AnimeEntry(
            name: "Movie",
            type: .movie,
            tmdbID: 31,
            detail: AnimeEntryDetail(
                language: Language.chinese.rawValue,
                title: "Movie",
                logoImageURL: URL(string: "https://example.com/logo-zh.png"),
                staff: [
                    AnimeEntryStaff(
                        id: 3,
                        name: "Staff Three",
                        role: "Theme Song Performance / Producer"
                    ),
                    AnimeEntryStaff(
                        id: 4,
                        name: "Staff Four",
                        role: "Visual Effects"
                    ),
                    AnimeEntryStaff(
                        id: 6,
                        name: "Staff Six",
                        role: "Production Design / Graphic Designer"
                    )
                ]
            )
        )

        await chineseViewModel.load(for: chineseEntry, language: .chinese, dataHandler: nil)

        #expect(
            chineseViewModel.staffCards.map(\.secondaryText)
                == ["主题曲演唱 / 制片人", "视觉效果", "制作设计 / 平面设计"]
        )
    }

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

    @Test @MainActor func testDeletionScrollTargetFallbacks() throws {
        let sortStrategyKey = String.librarySortStrategy
        let sortReversedKey = String.librarySortReversed
        let defaults = UserDefaults.standard
        let originalSortStrategy = defaults.object(forKey: sortStrategyKey)
        let originalSortReversed = defaults.object(forKey: sortReversedKey)

        defer {
            if let originalSortStrategy {
                defaults.set(originalSortStrategy, forKey: sortStrategyKey)
            } else {
                defaults.removeObject(forKey: sortStrategyKey)
            }

            if let originalSortReversed {
                defaults.set(originalSortReversed, forKey: sortReversedKey)
            } else {
                defaults.removeObject(forKey: sortReversedKey)
            }
        }

        func makeEntry(name: String, tmdbID: Int, day: Int) -> AnimeEntry {
            AnimeEntry(
                name: name,
                type: .movie,
                tmdbID: tmdbID,
                dateSaved: referenceDate(year: 2026, month: 1, day: day)
            )
        }

        func makeStore(with entries: [AnimeEntry]) throws -> LibraryStore {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            for entry in entries {
                try store.repository.newEntry(entry)
            }
            try store.refreshLibrary()
            return store
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: Int?

            #expect(store.deleteEntry(second) { scrolledID = $0 })
            #expect(scrolledID == first.tmdbID)
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: Int?

            #expect(store.deleteEntry(first) { scrolledID = $0 })
            #expect(scrolledID == second.tmdbID)
        }

        do {
            let first = makeEntry(name: "First", tmdbID: 1, day: 1)
            let second = makeEntry(name: "Second", tmdbID: 2, day: 2)
            let third = makeEntry(name: "Third", tmdbID: 3, day: 3)
            let store = try makeStore(with: [first, second, third])
            var scrolledID: Int?

            #expect(store.deleteEntry(third) { scrolledID = $0 })
            #expect(scrolledID == second.tmdbID)
        }

        do {
            let solo = makeEntry(name: "Solo", tmdbID: 10, day: 10)
            let store = try makeStore(with: [solo])
            var scrolledID: Int? = solo.tmdbID

            #expect(store.deleteEntry(solo) { scrolledID = $0 })
            #expect(scrolledID == nil)
        }
    }

    private func referenceDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
