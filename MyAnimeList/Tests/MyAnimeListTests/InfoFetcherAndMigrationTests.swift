//
//  InfoFetcherAndMigrationTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import SwiftData
import Testing

import struct TMDb.AggregrateCrewMember
import struct TMDb.CrewJob

@testable import DataProvider
@testable import MyAnimeList

struct InfoFetcherAndMigrationTests {
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
        let seriesID = 209867
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

    @Test func testAggregateStaffMappingMergesRepeatedCrewEntriesAndRetainsJobs() {
        let imagesConfiguration = makeImagesConfiguration()
        let staffDTOs = InfoFetcher.aggregateStaffDTOs(
            from: [
                AggregrateCrewMember(
                    id: 10,
                    name: "Creator",
                    originalName: "Creator Original",
                    gender: .unknown,
                    profilePath: nil,
                    jobs: [
                        CrewJob(creditID: "director", job: "Director", episodeCount: 12),
                        CrewJob(creditID: "music", job: "Music", episodeCount: 8)
                    ],
                    knownForDepartment: "Directing",
                    adult: nil,
                    totalEpisodeCount: 12,
                    popularity: nil
                ),
                AggregrateCrewMember(
                    id: 10,
                    name: "Creator",
                    originalName: "Creator Original",
                    gender: .unknown,
                    profilePath: nil,
                    jobs: [
                        CrewJob(creditID: "writer", job: "Writer", episodeCount: 10)
                    ],
                    knownForDepartment: "Writing",
                    adult: nil,
                    totalEpisodeCount: 10,
                    popularity: nil
                )
            ],
            imagesConfiguration: imagesConfiguration,
            language: .english
        )

        #expect(staffDTOs.count == 1)
        #expect(staffDTOs[0].id == 10)
        #expect(staffDTOs[0].role == "Directing")
        #expect(staffDTOs[0].jobs.map(\.job) == ["Director", "Music", "Writer"])
        #expect(staffDTOs[0].jobs.map(\.creditID) == ["director", "music", "writer"])
    }
}
