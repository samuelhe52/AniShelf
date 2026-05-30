//
//  InfoFetcherAndLibraryTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/21.
//

import Foundation
import TMDb
import Testing
import ZIPFoundation

import struct TMDb.AggregateCrewMember
import struct TMDb.CrewJob
import struct TMDb.ImageMetadata

@testable import DataProvider
@testable import MyAnimeList

struct InfoFetcherAndLibraryTests {
    let fetcher = InfoFetcher()
    let language: MyAnimeList.Language = .japanese

    @MainActor let dataProviderForPreview = DataProvider.forPreview
    @MainActor let backupManager = BackupManager(dataProvider: .forPreview)

    @Test func testFetchInfo() async throws {
        let result = try await fetcher.searchTVSeries(name: "Frieren", language: language).first
        try #require(result != nil, "No search results for 'Frieren'")
        let info = try await fetcher.tvSeriesInfo(tmdbID: result!.id, language: language)
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
        let images = try await fetcher.tmdbClient.tvSeries.images(forTVSeries: seriesID)
        let expectedPath = try #require(
            images.backdrops.first(where: { $0.languageCode == nil })?.filePath,
            "Expected at least one no-language backdrop"
        )
        let expectedURL = try await fetcher.tmdbClient.imagesConfiguration.backdropURL(
            for: expectedPath,
            idealWidth: 1_280
        )
        let actualURL = try await fetcher.detailInfo(
            entryType: .series,
            tmdbID: seriesID,
            language: language
        ).heroImageURL
        #expect(actualURL == expectedURL)
    }

    @Test func testPosterSelectionAllowsOnlyOriginalNoLanguageAndMetadataLanguage() throws {
        let englishPoster = URL(string: "https://example.com/poster-en.jpg")!
        let noLanguagePoster = URL(string: "https://example.com/poster-none.jpg")!
        let chinesePoster = URL(string: "https://example.com/poster-zh.jpg")!

        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [
                    .init(languageCode: "en", filePath: englishPoster),
                    .init(languageCode: nil, filePath: noLanguagePoster),
                    .init(languageCode: "zh", filePath: chinesePoster)
                ],
                originalLanguageCode: "zh",
                metadataLanguageCode: "en"
            ) == chinesePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [
                    .init(languageCode: "en", filePath: englishPoster),
                    .init(languageCode: nil, filePath: noLanguagePoster),
                    .init(languageCode: "zh", filePath: chinesePoster)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chinesePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [
                    .init(languageCode: "en", filePath: englishPoster),
                    .init(languageCode: "zh", filePath: chinesePoster)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chinesePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(from: [
                .init(languageCode: "en", filePath: englishPoster),
                .init(languageCode: nil, filePath: noLanguagePoster)
            ]) == noLanguagePoster
        )
        #expect(
            TMDbImageSelection.preferredPosterPath(
                from: [.init(languageCode: "en", filePath: englishPoster)],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == nil
        )
    }

    @Test func testPosterPickerFallsBackToAllPostersWhenNoLanguageMatches() {
        let englishPoster = ImageURLWithMetadata(
            metadata: ImageMetadata(
                filePath: URL(string: "/poster-en.jpg")!,
                width: 500,
                height: 750,
                aspectRatio: 2.0 / 3.0,
                voteAverage: nil,
                voteCount: nil,
                languageCode: "en"
            ),
            url: URL(string: "https://example.com/poster-en.jpg")!
        )
        let koreanPoster = ImageURLWithMetadata(
            metadata: ImageMetadata(
                filePath: URL(string: "/poster-ko.jpg")!,
                width: 900,
                height: 1_350,
                aspectRatio: 2.0 / 3.0,
                voteAverage: nil,
                voteCount: nil,
                languageCode: "ko"
            ),
            url: URL(string: "https://example.com/poster-ko.jpg")!
        )

        let posters = [englishPoster, koreanPoster].filteredAndSorted(
            originalLanguageCode: "ja",
            metadataLanguageCode: "zh"
        )

        #expect(posters.map(\.url) == [koreanPoster.url, englishPoster.url])
    }

    @Test func testLogoSelectionUsesNoLanguageAsFinalFallback() throws {
        let englishLogo = URL(string: "https://example.com/logo-en.png")!
        let noLanguageLogo = URL(string: "https://example.com/logo-none.png")!
        let chineseLogo = URL(string: "https://example.com/logo-zh.png")!
        let ignoredJPGLogo = URL(string: "https://example.com/logo-zh.jpg")!

        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "zh", filePath: ignoredJPGLogo),
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: nil, filePath: noLanguageLogo),
                    .init(languageCode: "zh", filePath: chineseLogo)
                ],
                originalLanguageCode: "zh",
                metadataLanguageCode: "en"
            ) == chineseLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: nil, filePath: noLanguageLogo),
                    .init(languageCode: "zh", filePath: chineseLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chineseLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: "zh", filePath: chineseLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "zh"
            ) == chineseLogo
        )
        #expect(
            TMDbImageSelection.preferredLogoPath(
                from: [
                    .init(languageCode: "en", filePath: englishLogo),
                    .init(languageCode: nil, filePath: noLanguageLogo)
                ],
                originalLanguageCode: "ja",
                metadataLanguageCode: "ko"
            ) == noLanguageLogo
        )
    }

    @Test func testAnimeEntryStoresOriginalLanguageCodeFromBasicInfo() {
        let entry = AnimeEntry(
            fromInfo: BasicInfo(
                name: "Frieren",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                originalLanguageCode: "ja",
                tmdbID: 20_9867,
                onAirDate: nil,
                linkToDetails: nil,
                type: .series
            )
        )

        #expect(entry.originalLanguageCode == "ja")
    }

    @Test func testMovieTranslationsMapTitleIntoNameDictionary() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 1,
                translations: [
                    Translation(
                        countryCode: "JP",
                        languageCode: "ja",
                        name: "Japanese",
                        englishName: "Japanese",
                        data: MovieTranslationData(title: "劇場版", overview: "映画の概要")
                    )
                ]
            )
        )

        #expect(result.name == ["ja-JP": "劇場版"])
        #expect(result.overview == ["ja-JP": "映画の概要"])
    }

    @Test func testTVSeriesTranslationsMapNameAndOverview() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 2,
                translations: [
                    Translation(
                        countryCode: "US",
                        languageCode: "en",
                        name: "English",
                        englishName: "English",
                        data: TVSeriesTranslationData(name: "Frieren", overview: "A journey continues")
                    )
                ]
            )
        )

        #expect(result.name == ["en-US": "Frieren"])
        #expect(result.overview == ["en-US": "A journey continues"])
    }

    @Test func testTVSeasonTranslationsMapNameAndOverview() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 3,
                translations: [
                    Translation(
                        countryCode: "TW",
                        languageCode: "zh",
                        name: "Traditional Chinese",
                        englishName: "Traditional Chinese",
                        data: TVSeasonTranslationData(name: "第一季", overview: "旅程開始")
                    )
                ]
            )
        )

        #expect(result.name == ["zh-TW": "第一季"])
        #expect(result.overview == ["zh-TW": "旅程開始"])
    }

    @Test func testTranslationDictionariesOmitMissingFields() {
        let result = fetcher.translationDictionaries(
            from: TranslationCollection(
                id: 4,
                translations: [
                    Translation(
                        countryCode: "JP",
                        languageCode: "ja",
                        name: "Japanese",
                        englishName: "Japanese",
                        data: OptionalTranslationData(name: nil, overview: "概要")
                    ),
                    Translation(
                        countryCode: "US",
                        languageCode: "en",
                        name: "English",
                        englishName: "English",
                        data: OptionalTranslationData(name: "Localized Title", overview: nil)
                    )
                ]
            ),
            name: { $0.name },
            overview: { $0.overview }
        )

        #expect(result.name == ["en-US": "Localized Title"])
        #expect(result.overview == ["ja-JP": "概要"])
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

    @Test @MainActor func testBackupUsesDeflateCompression() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelfTests-compressed-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let dataProvider = DataProvider(url: storeDirectory.appendingPathComponent("compressed.store"))
        let entry = AnimeEntry(
            name: "Compression Fixture",
            type: .movie,
            tmdbID: 400_003,
            dateSaved: referenceDate(year: 2026, month: 5, day: 19)
        )
        entry.notes = String(repeating: "backup compression fixture ", count: 1_024)
        try dataProvider.dataHandler.newEntry(entry)

        let backupURL = try BackupManager(dataProvider: dataProvider).createBackup()
        let archive = try Archive(url: backupURL, accessMode: .read)
        let storeEntry = try #require(
            archive.first { $0.path.hasSuffix("/compressed.store") }
        )

        #expect(storeEntry.compressedSize < storeEntry.uncompressedSize)
    }

    @Test @MainActor func testRestoreBackupDoesNotDeleteCurrentStoreWhenArchiveIsInvalid() throws {
        let fileManager = FileManager.default
        let storeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-restore-rollback-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: storeDirectory) }

        let dataProvider = DataProvider(url: storeDirectory.appendingPathComponent("restore.store"))
        let entry = AnimeEntry(
            name: "Keep Me",
            type: .movie,
            tmdbID: 400_004,
            dateSaved: referenceDate(year: 2026, month: 5, day: 20)
        )
        try dataProvider.dataHandler.newEntry(entry)
        #expect(try dataProvider.getAllModels(ofType: AnimeEntry.self).count == 1)

        let malformedRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-invalid-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: malformedRootURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: malformedRootURL) }

        let stagedBackupURL = malformedRootURL.appendingPathComponent("BrokenBackup", isDirectory: true)
        try fileManager.createDirectory(
            at: stagedBackupURL,
            withIntermediateDirectories: true
        )

        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(
            "AniShelf-invalid-\(UUID().uuidString).mallib"
        )
        defer { try? fileManager.removeItem(at: archiveURL) }
        try fileManager.zipItem(
            at: stagedBackupURL,
            to: archiveURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )

        let manager = BackupManager(dataProvider: dataProvider)

        #expect(throws: Error.self) {
            try manager.restoreBackup(from: archiveURL)
        }

        dataProvider.reloadDataStore()
        #expect(try dataProvider.getAllModels(ofType: AnimeEntry.self).map(\.tmdbID) == [400_004])
    }

    @Test @MainActor func testRestoreBackupReloadsCurrentSchemaLibraryAndAllowsSave() throws {
        let fileManager = FileManager.default
        let sourceDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-restore-source-\(UUID().uuidString)", isDirectory: true)
        let targetDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-restore-target-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: sourceDirectory)
            try? fileManager.removeItem(at: targetDirectory)
        }

        let sourceProvider = DataProvider(url: sourceDirectory.appendingPathComponent("library.store"))
        let restoredEntry = AnimeEntry(
            name: "Restored Cloud Library",
            type: .series,
            tmdbID: 500_001,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Restored Cloud Library",
                episodeCount: 12
            ),
            dateSaved: referenceDate(year: 2026, month: 5, day: 27),
            dateStarted: referenceDate(year: 2026, month: 5, day: 28),
            score: 4,
            usingCustomPoster: true
        )
        restoredEntry.favorite = true
        restoredEntry.notes = "Restored notes"
        restoredEntry.setEpisodeProgress(
            seasonNumber: 1,
            watchedThroughEpisode: 7,
            now: referenceDate(year: 2026, month: 5, day: 29)
        )
        try sourceProvider.dataHandler.newEntry(restoredEntry)
        let backupURL = try BackupManager(dataProvider: sourceProvider).createBackup()
        defer { try? fileManager.removeItem(at: backupURL) }

        let targetProvider = DataProvider(url: targetDirectory.appendingPathComponent("library.store"))
        try targetProvider.dataHandler.newEntry(
            AnimeEntry(name: "Replace Me", type: .movie, tmdbID: 500_002)
        )

        try BackupManager(dataProvider: targetProvider).restoreBackup(from: backupURL)
        let entries = try targetProvider.getAllModels(ofType: AnimeEntry.self)
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.tmdbID == 500_001)
        #expect(entry.notes == "Restored notes")
        #expect(entry.favorite)
        #expect(entry.score == 4)
        #expect(entry.usingCustomPoster)
        #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 7)

        entry.notes = "Saved after restore"
        try targetProvider.dataHandler.modelContext.save()
        targetProvider.reloadDataStore()
        #expect(try targetProvider.getAllModels(ofType: AnimeEntry.self).first?.notes == "Saved after restore")
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

    @Test @MainActor func testExistingEntryPrefersReferencedHiddenParentOverOrphanDuplicate() throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)

        let orphanHiddenParent = AnimeEntry(
            name: "Orphan Hidden Parent",
            type: .series,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        orphanHiddenParent.onDisplay = false
        try repository.newEntry(orphanHiddenParent)

        let referencedHiddenParent = AnimeEntry(
            name: "Referenced Hidden Parent",
            type: .series,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 2)
        )
        referencedHiddenParent.onDisplay = false
        try repository.newEntry(referencedHiddenParent)

        let seasonEntry = AnimeEntry(
            name: "Frieren Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209867),
            tmdbID: 307972,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        seasonEntry.parentSeriesEntry = referencedHiddenParent
        try repository.newEntry(seasonEntry)

        let resolvedEntry = try #require(repository.existingEntry(tmdbID: 209867))
        #expect(resolvedEntry.id == referencedHiddenParent.id)
    }

    @Test @MainActor func testConvertSeasonToSeriesPreservesScoreAndDateTrackingSetting() async throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let converter = LibraryEntryConverter(repository: repository)
        let seasonEntry = AnimeEntry(
            name: "Frieren Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209867),
            tmdbID: 400_234
        )
        seasonEntry.setScore(5)
        seasonEntry.isDateTrackingEnabled = false
        seasonEntry.dateStarted = referenceDate(year: 2026, month: 5, day: 1)
        seasonEntry.dateFinished = referenceDate(year: 2026, month: 5, day: 2)
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
        #expect(!seriesEntry.isDateTrackingEnabled)
        #expect(seriesEntry.dateStarted == referenceDate(year: 2026, month: 5, day: 1))
        #expect(seriesEntry.dateFinished == referenceDate(year: 2026, month: 5, day: 2))
    }

    @Test @MainActor func testConvertSeriesToSeasonPreservesScoreAndDateTrackingSetting() async throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let converter = LibraryEntryConverter(repository: repository)
        let seriesEntry = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209867
        )
        seriesEntry.setScore(2)
        seriesEntry.isDateTrackingEnabled = false
        seriesEntry.dateStarted = referenceDate(year: 2026, month: 5, day: 3)
        seriesEntry.dateFinished = referenceDate(year: 2026, month: 5, day: 4)
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
        #expect(!seasonEntry.isDateTrackingEnabled)
        #expect(seasonEntry.dateStarted == referenceDate(year: 2026, month: 5, day: 3))
        #expect(seasonEntry.dateFinished == referenceDate(year: 2026, month: 5, day: 4))
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
                AggregateCrewMember(
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
                    isAdultOnly: nil,
                    totalEpisodeCount: 12,
                    popularity: nil
                ),
                AggregateCrewMember(
                    id: 10,
                    name: "Creator",
                    originalName: "Creator Original",
                    gender: .unknown,
                    profilePath: nil,
                    jobs: [
                        CrewJob(creditID: "writer", job: "Writer", episodeCount: 10)
                    ],
                    knownForDepartment: "Writing",
                    isAdultOnly: nil,
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
        #expect(staffDTOs[0].jobs.map { $0.job } == ["Director", "Music", "Writer"])
        #expect(staffDTOs[0].jobs.map { $0.creditID } == ["director", "music", "writer"])
    }

    private struct OptionalTranslationData: Codable, Equatable, Hashable, Sendable {
        let name: String?
        let overview: String?
    }
}
