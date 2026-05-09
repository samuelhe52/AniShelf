//
//  MyAnimeListTests.swift
//  MyAnimeListTests
//
//  Created by Samuel He on 2024/12/8.
//

import Foundation
import SwiftData
import Testing
import UIKit
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

    @Test func testEntryScoreRoundTripAndChangeDetection() throws {
        let entry = AnimeEntry.template(id: 101)
        let originalUserInfo = entry.userInfo

        entry.setScore(4)
        #expect(entry.score == 4)
        #expect(entry.userInfo.score == 4)
        #expect(entry.userInfoHasChanges(comparedTo: originalUserInfo))

        let encoded = try JSONEncoder().encode(entry.userInfo)
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: encoded)
        #expect(decoded == entry.userInfo)

        let restored = AnimeEntry.template(id: 202)
        restored.updateUserInfo(from: decoded)
        #expect(restored.score == 4)
        #expect(restored.userInfo == decoded)

        entry.setScore(nil)
        #expect(entry.score == nil)
        #expect(!entry.userInfoHasChanges(comparedTo: originalUserInfo))
    }

    @Test func testEntryScoreNormalizationRejectsOutOfRangeValues() throws {
        let entry = AnimeEntry.template(id: 303)
        entry.setScore(9)

        #expect(entry.score == nil)

        entry.setScore(1)
        #expect(entry.score == 1)

        var payload = try #require(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(entry.userInfo)
            ) as? [String: Any]
        )
        payload["score"] = 99

        let invalidData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(UserEntryInfo.self, from: invalidData)
        #expect(decoded.score == nil)
    }

    @Test @MainActor func testUserEntryInfoPasteboardRoundTripPreservesScore() throws {
        let pasteboard = UIPasteboard.general
        let originalItems = pasteboard.items
        defer { pasteboard.items = originalItems }

        let entry = AnimeEntry.template(id: 404)
        entry.setScore(5)
        entry.notes = "Keep this"

        entry.userInfo.copyToPasteboard()

        let pasted = try #require(UserEntryInfo.fromPasteboard())
        #expect(pasted.score == 5)
        #expect(pasted.notes == "Keep this")
    }

    @Test @MainActor func testScoreMigrationFromV271DefaultsToNil() throws {
        let storeURL = temporaryStoreURL(name: "score-migration")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_1.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)
        let legacyEntry = SchemaV2_7_1.AnimeEntry(
            name: "Legacy Entry",
            type: .movie,
            tmdbID: 7_777,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        legacyEntry.notes = "Migrated notes"
        legacyEntry.favorite = true
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)
        let migratedEntry = try #require(migratedEntries.first)

        #expect(migratedEntry.tmdbID == 7_777)
        #expect(migratedEntry.notes == "Migrated notes")
        #expect(migratedEntry.favorite)
        #expect(migratedEntry.score == nil)
    }

    @Test @MainActor func testConvertSeasonToSeriesPreservesScore() async throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let converter = LibraryEntryConverter(repository: repository)
        let seasonEntry = AnimeEntry(
            name: "Frieren Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209867),
            tmdbID: 400_234
        )
        seasonEntry.setScore(5)
        seasonEntry.notes = "Season-side score"
        try repository.newEntry(seasonEntry)

        try await converter.convertSeasonToSeries(
            seasonEntry,
            language: .english,
            fetcher: fetcher
        )

        let migratedEntries = try dataProvider.getAllModels(ofType: AnimeEntry.self)
        let seriesEntry = try #require(
            migratedEntries.first(where: { $0.tmdbID == 209867 && $0.onDisplay })
        )

        #expect(seriesEntry.score == 5)
        #expect(seriesEntry.notes == "Season-side score")
    }

    @Test @MainActor func testConvertSeriesToSeasonPreservesScore() async throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let converter = LibraryEntryConverter(repository: repository)
        let seriesEntry = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209867
        )
        seriesEntry.setScore(2)
        seriesEntry.notes = "Series-side score"
        try repository.newEntry(seriesEntry)

        try await converter.convertSeriesToSeason(
            seriesEntry,
            seasonNumber: 1,
            language: .english,
            fetcher: fetcher
        )

        let migratedEntries = try dataProvider.getAllModels(ofType: AnimeEntry.self)
        let seasonEntry = try #require(
            migratedEntries.first {
                guard case .season(let seasonNumber, let parentSeriesID) = $0.type else {
                    return false
                }
                return seasonNumber == 1 && parentSeriesID == 209867 && $0.onDisplay
            }
        )
        let hiddenSeriesEntry = try #require(
            migratedEntries.first(where: { $0.tmdbID == 209867 && $0.type == .series && !$0.onDisplay })
        )

        #expect(seasonEntry.score == 2)
        #expect(seasonEntry.notes == "Series-side score")
        #expect(hiddenSeriesEntry.tmdbID == 209867)
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

    @Test @MainActor func testWhatsNewDoesNotAutoShowWithoutRegisteredEntry() {
        let suiteName = "MyAnimeListTests.WhatsNew.NoEntry"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = makeWhatsNewController(
            defaults: defaults,
            currentVersion: "1.54",
            entries: [:]
        )

        controller.presentIfNeeded(allowsAutoPresentation: true)

        #expect(controller.currentEntry == nil)
        #expect(controller.presentedEntry == nil)
        #expect(String.allPreferenceKeys.contains(.lastSeenWhatsNewVersion))
    }

    @Test @MainActor func testWhatsNewAutoShowsOnceForRegisteredVersion() {
        let suiteName = "MyAnimeListTests.WhatsNew.AutoShow"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = makeWhatsNewEntry(version: "1.54")
        let controller = makeWhatsNewController(
            defaults: defaults,
            currentVersion: "1.54",
            entries: [entry.version: entry]
        )

        controller.presentIfNeeded(allowsAutoPresentation: true)

        #expect(controller.currentEntry?.version == entry.version)
        #expect(controller.presentedEntry?.version == entry.version)
    }

    @Test @MainActor func testWhatsNewDismissalMarksSeenAndSuppressesRepeatAutoPresentation() {
        let suiteName = "MyAnimeListTests.WhatsNew.Dismissal"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = makeWhatsNewEntry(version: "1.54")
        let firstController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )
        firstController.presentIfNeeded(allowsAutoPresentation: true)
        firstController.dismissPresentedEntry()

        #expect(defaults.string(forKey: .lastSeenWhatsNewVersion) == entry.version)
        #expect(firstController.presentedEntry == nil)

        let secondController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )
        secondController.presentIfNeeded(allowsAutoPresentation: true)

        #expect(secondController.presentedEntry == nil)
    }

    @Test @MainActor func testWhatsNewUpdateOnlyAutoShowsWhenNewVersionHasEntry() {
        let suiteName = "MyAnimeListTests.WhatsNew.VersionUpdates"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("1.53", forKey: .lastSeenWhatsNewVersion)

        let missingEntryController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: "1.54",
            entries: [:]
        )
        missingEntryController.presentIfNeeded(allowsAutoPresentation: true)

        let entry = makeWhatsNewEntry(version: "1.55")
        let newVersionController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )
        newVersionController.presentIfNeeded(allowsAutoPresentation: true)

        #expect(missingEntryController.presentedEntry == nil)
        #expect(newVersionController.presentedEntry?.version == entry.version)
    }

    @Test @MainActor func testWhatsNewManualReopenRemainsAvailableAfterDismissal() {
        let suiteName = "MyAnimeListTests.WhatsNew.ManualReopen"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = makeWhatsNewEntry(version: "1.54")
        let controller = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )

        controller.presentIfNeeded(allowsAutoPresentation: true)
        controller.dismissPresentedEntry()
        controller.presentCurrentEntry()

        #expect(controller.currentEntry?.version == entry.version)
        #expect(controller.presentedEntry?.version == entry.version)
    }

    @Test @MainActor func testWhatsNewRefreshMetadataActionUsesSettingsRefreshPath() {
        let defaults = UserDefaults.standard
        let key = String.libraryHideDroppedByDefault
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(true, forKey: key)

        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        var refreshCallCount = 0
        var capturedOptions: LibraryRefreshOptions?
        var openedURL: URL?
        let actions = LibraryProfileSettingsActions(
            store: store,
            refreshInfosHandler: { _, options in
                refreshCallCount += 1
                capturedOptions = options
            }
        )

        let runner = actions.makeWhatsNewActionRunner()
        runner.run(.refreshMetadata) { url in
            openedURL = url
        }

        #expect(refreshCallCount == 1)
        #expect(capturedOptions?.prefetchImages == true)
        #expect(openedURL == nil)
        #expect(defaults.bool(forKey: key))
    }

    @Test @MainActor func testWhatsNewRefreshActionTracksInlineProgressState() {
        var capturedOptions: LibraryRefreshOptions?
        var refreshRunCount = 0
        let runner = WhatsNewActionRunner { options in
            refreshRunCount += 1
            capturedOptions = options
        }

        runner.run(.refreshMetadata) { _ in
            Issue.record("Refresh action should not open a URL.")
        }

        guard let capturedOptions else {
            Issue.record("Expected refresh options to be captured.")
            return
        }

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == 0)
        default:
            Issue.record("Expected refresh to enter an in-progress state immediately.")
        }

        capturedOptions.reporter.report(
            .metadataProgress(
                current: 2,
                total: 4,
                messageResource: "Fetching Info: 2 / 4"
            )
        )

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == 0.5)
        default:
            Issue.record("Expected metadata progress to keep the action in progress.")
        }

        capturedOptions.reporter.report(
            .organizingLibrary(messageResource: "Organizing Library...")
        )

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == nil)
        default:
            Issue.record("Expected organizing state to be reflected inline.")
        }

        capturedOptions.reporter.report(
            .metadataPhaseComplete(
                .init(
                    state: .completed,
                    messageResource: "Refreshed infos for 4 entries.",
                    successfulItemCount: 4,
                    failedItemCount: 0
                )
            )
        )

        switch runner.refreshState {
        case .inProgress:
            break
        default:
            Issue.record("Expected metadata phase completion to remain non-terminal inline.")
        }

        capturedOptions.reporter.report(
            .imagePrefetchProgress(
                current: 3,
                total: 6,
                messageResource: "Fetching Images: 3 / 6"
            )
        )

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == 0.5)
        default:
            Issue.record("Expected image prefetch progress to continue inline.")
        }

        capturedOptions.reporter.report(
            .imagePrefetchPhaseComplete(
                .init(
                    state: .completed,
                    messageResource: "Fetched: 6, failed: 0",
                    successfulItemCount: 6,
                    failedItemCount: 0
                )
            )
        )

        switch runner.refreshState {
        case .inProgress:
            break
        default:
            Issue.record("Expected image prefetch phase completion to remain non-terminal inline.")
        }

        capturedOptions.reporter.report(
            .refreshComplete(
                .init(
                    state: .completed,
                    messageResource: "Refreshed 4 entries and fetched 6 images."
                )
            )
        )

        switch runner.refreshState {
        case .completed(let completion):
            #expect(completion.state == .completed)
        default:
            Issue.record("Expected a completed inline refresh state after image prefetch completion.")
        }

        runner.run(.refreshMetadata) { _ in
            Issue.record("Completed refresh CTA should stay disabled.")
        }
        #expect(refreshRunCount == 1)

        capturedOptions.reporter.report(
            .imagePrefetchProgress(
                current: 6,
                total: 6,
                messageResource: "Fetching Images: 6 / 6"
            )
        )

        switch runner.refreshState {
        case .completed(let completion):
            #expect(completion.state == .completed)
        default:
            Issue.record("Late progress should not override completed inline refresh state.")
        }
    }

    @Test @MainActor func testToastReporterIgnoresLateProgressAfterRefreshCompletion() {
        let originalCenter = ToastCenter.global
        let center = ToastCenter()
        ToastCenter.global = center
        defer { ToastCenter.global = originalCenter }

        let reporter = LibraryRefreshReporter.toast

        reporter.report(
            .imagePrefetchProgress(
                current: 2,
                total: 4,
                messageResource: "Fetching Images: 2 / 4"
            )
        )
        #expect(center.progressState?.current == 2)

        reporter.report(
            .refreshComplete(
                .init(
                    state: .completed,
                    messageResource: "Refreshed 4 entries and fetched 6 images."
                )
            )
        )

        #expect(center.progressState == nil)
        #expect(center.loadingMessage == nil)
        #expect(center.completionState?.state == .completed)

        reporter.report(
            .imagePrefetchProgress(
                current: 4,
                total: 4,
                messageResource: "Fetching Images: 4 / 4"
            )
        )

        #expect(center.progressState == nil)
        #expect(center.completionState?.state == .completed)
    }

    @Test @MainActor func testStandaloneImagePrefetchReportsRefreshCompletion() async throws {
        func isRefreshComplete(_ event: LibraryRefreshEvent) -> Bool {
            if case .refreshComplete = event {
                true
            } else {
                false
            }
        }

        var events: [LibraryRefreshEvent] = []
        let reporter = LibraryRefreshReporter { event in
            events.append(event)
        }

        LibraryImageCacheService.prefetchImages(for: [AnimeEntry](), reporter: reporter)

        for _ in 0..<20 {
            if events.contains(where: isRefreshComplete) {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(
            events.contains { event in
                if case .imagePrefetchProgress = event {
                    true
                } else {
                    false
                }
            })
        #expect(
            events.contains { event in
                if case .imagePrefetchPhaseComplete = event {
                    true
                } else {
                    false
                }
            })

        guard
            let completion = events.compactMap({ event -> LibraryRefreshCompletion? in
                if case .refreshComplete(let completion) = event {
                    completion
                } else {
                    nil
                }
            }).first
        else {
            Issue.record("Standalone image prefetch should report overall refresh completion.")
            return
        }
        #expect(completion.state == .completed)
        #expect(completion.successfulItemCount == 0)
        #expect(completion.failedItemCount == 0)
    }

    @Test @MainActor func testStandaloneImagePrefetchToastClearsProgressOnCompletion() async throws {
        let originalCenter = ToastCenter.global
        let center = ToastCenter()
        ToastCenter.global = center
        defer { ToastCenter.global = originalCenter }

        LibraryImageCacheService.prefetchImages(for: [AnimeEntry](), reporter: .toast)

        for _ in 0..<20 {
            if center.completionState != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(center.progressState == nil)
        #expect(center.loadingMessage == nil)
        #expect(center.completionState?.state == .completed)
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

    @Test @MainActor func testWatchStatusGroupingUsesCurrentSortWithinBuckets() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .watchStatus
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            let entries = [
                makeLibraryEntry(name: "Watched Early", tmdbID: 31, watchStatus: .watched, daySaved: 1),
                makeLibraryEntry(name: "Watching Early", tmdbID: 11, watchStatus: .watching, daySaved: 2),
                makeLibraryEntry(name: "Dropped", tmdbID: 41, watchStatus: .dropped, daySaved: 3),
                makeLibraryEntry(name: "Watching Late", tmdbID: 12, watchStatus: .watching, daySaved: 4),
                makeLibraryEntry(name: "Planned", tmdbID: 21, watchStatus: .planToWatch, daySaved: 5),
                makeLibraryEntry(name: "Watched Late", tmdbID: 32, watchStatus: .watched, daySaved: 6)
            ]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [11, 12, 21, 31, 32, 41])
        }
    }

    @Test @MainActor func testScoreGroupingPlacesUnscoredEntriesLast() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .score
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            let entries = [
                makeLibraryEntry(name: "Unscored", tmdbID: 61, daySaved: 1),
                makeLibraryEntry(name: "Score Five Early", tmdbID: 51, daySaved: 2, score: 5),
                makeLibraryEntry(name: "Score Three", tmdbID: 31, daySaved: 3, score: 3),
                makeLibraryEntry(name: "Score Two", tmdbID: 21, daySaved: 4, score: 2),
                makeLibraryEntry(name: "Score Five Late", tmdbID: 52, daySaved: 5, score: 5),
                makeLibraryEntry(name: "Score Four", tmdbID: 41, daySaved: 6, score: 4),
                makeLibraryEntry(name: "Score One", tmdbID: 11, daySaved: 7, score: 1)
            ]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [51, 52, 41, 31, 21, 11, 61])
        }
    }

    @Test @MainActor func testFavoriteGroupingKeepsBucketOrderWhenReversed() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .favorite
            store.sortStrategy = .dateSaved
            store.sortReversed = false

            let favoriteEarly = makeLibraryEntry(
                name: "Favorite Early",
                tmdbID: 71,
                daySaved: 1,
                favorite: true
            )
            let otherEarly = makeLibraryEntry(name: "Other Early", tmdbID: 81, daySaved: 2)
            let favoriteLate = makeLibraryEntry(
                name: "Favorite Late",
                tmdbID: 72,
                daySaved: 3,
                favorite: true
            )
            let otherLate = makeLibraryEntry(name: "Other Late", tmdbID: 82, daySaved: 4)
            let entries = [favoriteEarly, otherEarly, favoriteLate, otherLate]

            #expect(store.filterAndSort(entries).map(\.tmdbID) == [71, 72, 81, 82])

            store.sortReversed = true
            #expect(store.filterAndSort(entries).map(\.tmdbID) == [72, 71, 82, 81])
        }
    }

    @Test @MainActor func testNoGroupingMatchesCurrentFlatSortBehavior() throws {
        try withRestoredLibrarySortingPreferences {
            let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
            store.groupStrategy = .none
            store.sortStrategy = .dateSaved
            store.sortReversed = true

            let entries = [
                makeLibraryEntry(name: "Favorite", tmdbID: 91, daySaved: 1, favorite: true),
                makeLibraryEntry(name: "Watched", tmdbID: 92, watchStatus: .watched, daySaved: 4),
                makeLibraryEntry(name: "Watching", tmdbID: 93, watchStatus: .watching, daySaved: 2),
                makeLibraryEntry(name: "Scored", tmdbID: 94, daySaved: 3, score: 5)
            ]

            let expected = Array(entries.sorted(by: LibraryStore.AnimeSortStrategy.dateSaved.compare).reversed())
            #expect(store.filterAndSort(entries).map(\.tmdbID) == expected.map(\.tmdbID))
        }
    }

    @MainActor
    private func makeWhatsNewController(
        defaults: UserDefaults,
        currentVersion: String,
        entries: [String: WhatsNewEntry]
    ) -> WhatsNewController {
        WhatsNewController(
            defaults: defaults,
            currentVersion: currentVersion,
            entryProvider: { entries[$0] }
        )
    }

    private func makeWhatsNewEntry(version: String) -> WhatsNewEntry {
        WhatsNewEntry(
            version: version,
            title: "Version \(version)",
            summary: "Release summary",
            highlights: ["A highlight"],
            primaryAction: .init(
                id: "refresh",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            )
        )
    }

    private func referenceDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    @MainActor
    private func withRestoredLibrarySortingPreferences(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = [
            String.libraryGroupStrategy,
            String.librarySortStrategy,
            String.librarySortReversed
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

        try body()
    }

    private func makeLibraryEntry(
        name: String,
        tmdbID: Int,
        watchStatus: AnimeEntry.WatchStatus = .planToWatch,
        daySaved: Int,
        score: Int? = nil,
        favorite: Bool = false
    ) -> AnimeEntry {
        let entry = AnimeEntry(
            name: name,
            type: .movie,
            tmdbID: tmdbID,
            dateSaved: referenceDate(year: 2026, month: 1, day: daySaved),
            score: score
        )
        entry.watchStatus = watchStatus
        entry.favorite = favorite
        return entry
    }

    private func temporaryStoreURL(name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelfTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("store.sqlite")
    }
}
