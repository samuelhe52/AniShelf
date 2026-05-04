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

    @Test @MainActor func testDeletionScrollTargetFallbacks() {
        let interaction = LibraryEntryInteractionState()
        let first = AnimeEntry(name: "First", type: .movie, tmdbID: 1)
        let second = AnimeEntry(name: "Second", type: .movie, tmdbID: 2)
        let third = AnimeEntry(name: "Third", type: .movie, tmdbID: 3)
        let entries = [first, second, third]

        #expect(interaction.deletionScrollTarget(for: second, in: entries) == .entry(1))
        #expect(interaction.deletionScrollTarget(for: first, in: entries) == .entry(2))
        #expect(interaction.deletionScrollTarget(for: third, in: entries) == .entry(2))
        #expect(interaction.deletionScrollTarget(for: first, in: [first]) == .clear)
        #expect(
            interaction.deletionScrollTarget(
                for: AnimeEntry(name: "Missing", type: .movie, tmdbID: 99),
                in: entries
            ) == .preserveCurrent
        )
    }

    private func referenceDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
