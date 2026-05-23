import Foundation
import SwiftData
import Testing

@testable import DataProvider

struct MigrationTests {
    @Test @MainActor func scoreMigrationFromV271DefaultsToNil() throws {
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

    @Test @MainActor func originalLanguageCodeMigrationFromV275DefaultsToNil() throws {
        let storeURL = temporaryStoreURL(name: "original-language-code-migration")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_5.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)
        let legacyEntry = SchemaV2_7_5.AnimeEntry(
            name: "Legacy Entry",
            type: .series,
            tmdbID: 8_888,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)
        let migratedEntry = try #require(migratedEntries.first)

        #expect(migratedEntry.tmdbID == 8_888)
        #expect(migratedEntry.originalLanguageCode == nil)
    }

    @Test @MainActor func detailGraphMigrationFromV260PreservesFieldsAndParentLinks() throws {
        let storeURL = temporaryStoreURL(name: "detail-graph-migration-v260")

        let legacySchema = Schema(versionedSchema: SchemaV2_6_0.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)

        let parentDetail = LegacyAnimeEntryDetailPayload(
            language: "en-US",
            title: "Frieren",
            subtitle: "Beyond Journey's End",
            overview: "An elf mage reflects on a long adventure.",
            status: "Ended",
            airDate: referenceDate(year: 2023, month: 9, day: 29),
            primaryLinkURL: URL(string: "https://example.com/frieren")!,
            heroImageURL: URL(string: "https://example.com/frieren-hero.jpg")!,
            logoImageURL: URL(string: "https://example.com/frieren-logo.png")!,
            genreIDs: [16, 18],
            voteAverage: 8.9,
            runtimeMinutes: 24,
            episodeCount: 28,
            seasonCount: 1,
            characters: [
                LegacyAnimeEntryCharacterPayload(
                    id: 101,
                    characterName: "Frieren",
                    actorName: "Atsumi Tanezaki",
                    profileURL: URL(string: "https://example.com/characters/frieren")
                )
            ],
            seasons: [
                LegacyAnimeEntrySeasonSummaryPayload(
                    id: 201,
                    seasonNumber: 1,
                    title: "Season 1",
                    posterURL: URL(string: "https://example.com/seasons/1.jpg")
                )
            ],
            episodes: [
                LegacyAnimeEntryEpisodeSummaryPayload(
                    id: 301,
                    episodeNumber: 1,
                    title: "The Journey's End",
                    airDate: referenceDate(year: 2023, month: 9, day: 29),
                    imageURL: URL(string: "https://example.com/episodes/1.jpg")
                ),
                LegacyAnimeEntryEpisodeSummaryPayload(
                    id: 302,
                    episodeNumber: 2,
                    title: "A New Adventure",
                    airDate: referenceDate(year: 2023, month: 10, day: 6),
                    imageURL: URL(string: "https://example.com/episodes/2.jpg")
                )
            ]
        )

        let seriesEntry = SchemaV2_6_0.AnimeEntry(
            name: "Frieren",
            nameTranslations: ["ja-JP": "葬送のフリーレン"],
            overview: "Series overview",
            overviewTranslations: ["ja-JP": "シリーズ概要"],
            onAirDate: referenceDate(year: 2023, month: 9, day: 29),
            type: .series,
            linkToDetails: URL(string: "https://example.com/series")!,
            posterURL: URL(string: "https://example.com/posters/series.jpg")!,
            backdropURL: URL(string: "https://example.com/backdrops/series.jpg")!,
            tmdbID: 209867,
            detail: parentDetail,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1),
            dateStarted: referenceDate(year: 2026, month: 5, day: 2),
            dateFinished: referenceDate(year: 2026, month: 5, day: 3),
            usingCustomPoster: true
        )
        seriesEntry.watchStatus = .watched
        seriesEntry.favorite = true
        seriesEntry.notes = "Series notes"

        let seasonEntry = SchemaV2_6_0.AnimeEntry(
            name: "Frieren Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209867),
            tmdbID: 307972,
            dateSaved: referenceDate(year: 2026, month: 5, day: 4),
            dateStarted: referenceDate(year: 2026, month: 5, day: 5),
            dateFinished: referenceDate(year: 2026, month: 5, day: 6)
        )
        seasonEntry.parentSeriesEntry = seriesEntry
        seasonEntry.watchStatus = .dropped
        seasonEntry.onDisplay = false
        seasonEntry.notes = "Season notes"

        legacyContainer.mainContext.insert(seriesEntry)
        legacyContainer.mainContext.insert(seasonEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)

        let migratedSeries = try #require(
            migratedEntries.first(where: { $0.tmdbID == 209867 && $0.type == .series })
        )
        let migratedSeason = try #require(
            migratedEntries.first {
                guard case .season(let seasonNumber, let parentSeriesID) = $0.type else {
                    return false
                }
                return seasonNumber == 1 && parentSeriesID == 209867
            }
        )
        let migratedDetail = try #require(migratedSeries.detail)

        #expect(migratedEntries.count == 2)
        #expect(migratedSeason.parentSeriesEntry?.id == migratedSeries.id)
        #expect(migratedSeries.nameTranslations["ja-JP"] == "葬送のフリーレン")
        #expect(migratedSeries.overviewTranslations["ja-JP"] == "シリーズ概要")
        #expect(migratedSeries.favorite)
        #expect(migratedSeries.notes == "Series notes")
        #expect(migratedSeries.usingCustomPoster)
        #expect(migratedSeries.watchStatus == .watched)
        #expect(migratedSeries.score == nil)
        #expect(migratedSeason.watchStatus == .dropped)
        #expect(migratedSeason.onDisplay == false)
        #expect(migratedSeason.notes == "Season notes")
        #expect(migratedSeason.score == nil)

        #expect(migratedDetail.language == "en-US")
        #expect(migratedDetail.title == "Frieren")
        #expect(migratedDetail.subtitle == "Beyond Journey's End")
        #expect(migratedDetail.status == "Ended")
        #expect(migratedDetail.primaryLinkURL == URL(string: "https://example.com/frieren")!)
        #expect(migratedDetail.logoImageURL == URL(string: "https://example.com/frieren-logo.png")!)
        #expect(migratedDetail.genreIDs == [16, 18])
        #expect(migratedDetail.voteAverage == 8.9)
        #expect(migratedDetail.runtimeMinutes == 24)
        #expect(migratedDetail.episodeCount == 28)
        #expect(migratedDetail.seasonCount == 1)
        #expect(migratedDetail.orderedCharacters.map(\.id) == [101])
        #expect(migratedDetail.orderedStaff.isEmpty)
        #expect(migratedDetail.seasons.map(\.id) == [201])
        #expect(migratedDetail.orderedEpisodes.map(\.id) == [301, 302])
    }

    @Test @MainActor func detailOrderingMigrationFromV270PreservesChildOrderAndStaffData() throws {
        let storeURL = temporaryStoreURL(name: "detail-ordering-migration-v270")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_0.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)

        let legacyDetail = SchemaV2_7_0.AnimeEntryDetail(
            language: "en-US",
            title: "Legacy Detail",
            subtitle: "Ordered Children",
            characters: [
                SchemaV2_7_0.AnimeEntryCharacter(id: 30, characterName: "Third", actorName: "Actor C"),
                SchemaV2_7_0.AnimeEntryCharacter(id: 10, characterName: "First", actorName: "Actor A"),
                SchemaV2_7_0.AnimeEntryCharacter(id: 20, characterName: "Second", actorName: "Actor B")
            ],
            staff: [
                SchemaV2_7_0.AnimeEntryStaff(
                    id: 200,
                    name: "Second",
                    role: "Director",
                    department: "Directing",
                    profileURL: URL(string: "https://example.com/staff/200")
                ),
                SchemaV2_7_0.AnimeEntryStaff(
                    id: 100,
                    name: "First",
                    role: "Writer",
                    department: "Writing",
                    profileURL: URL(string: "https://example.com/staff/100")
                )
            ],
            seasons: [
                SchemaV2_7_0.AnimeEntrySeasonSummary(id: 2, seasonNumber: 2, title: "Season 2"),
                SchemaV2_7_0.AnimeEntrySeasonSummary(id: 1, seasonNumber: 1, title: "Season 1")
            ],
            episodes: [
                SchemaV2_7_0.AnimeEntryEpisodeSummary(id: 2, episodeNumber: 2, title: "Episode 2"),
                SchemaV2_7_0.AnimeEntryEpisodeSummary(id: 1, episodeNumber: 1, title: "Episode 1")
            ]
        )
        let legacyEntry = SchemaV2_7_0.AnimeEntry(
            name: "Ordered Entry",
            type: .series,
            tmdbID: 500001,
            detail: legacyDetail,
            dateSaved: referenceDate(year: 2026, month: 5, day: 7)
        )
        legacyEntry.watchStatus = .watching
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)
        let migratedEntry = try #require(migratedEntries.first(where: { $0.tmdbID == 500001 }))
        let migratedDetail = try #require(migratedEntry.detail)
        let migratedStaffByID = Dictionary(
            uniqueKeysWithValues: migratedDetail.orderedStaff.map { ($0.id, $0) }
        )

        #expect(migratedEntry.watchStatus == .watching)
        #expect(migratedDetail.orderedCharacters.map(\.id).sorted() == [10, 20, 30])
        #expect(migratedDetail.orderedStaff.map(\.id).sorted() == [100, 200])
        #expect(migratedDetail.orderedEpisodes.map(\.id) == [1, 2])
        #expect(migratedDetail.seasons.map(\.seasonNumber).sorted() == [1, 2])
        #expect(migratedStaffByID[200]?.role == "Director")
        #expect(migratedStaffByID[100]?.department == "Writing")
        #expect(migratedDetail.orderedStaff.allSatisfy { $0.orderedJobs.isEmpty })
    }

    @Test @MainActor func parentSeriesCleanupMigrationDeduplicatesHiddenParents() throws {
        let storeURL = temporaryStoreURL(name: "parent-series-cleanup-migration")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_3.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)

        let visibleSeries = SchemaV2_7_3.AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 9)
        )
        let hiddenParentA = SchemaV2_7_3.AnimeEntry(
            name: "Frieren Hidden A",
            type: .series,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        hiddenParentA.onDisplay = false
        let hiddenParentB = SchemaV2_7_3.AnimeEntry(
            name: "Frieren Hidden B",
            type: .series,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 2)
        )
        hiddenParentB.onDisplay = false
        let seasonOne = SchemaV2_7_3.AnimeEntry(
            name: "Frieren Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209867),
            tmdbID: 307972,
            dateSaved: referenceDate(year: 2026, month: 5, day: 3)
        )
        seasonOne.parentSeriesEntry = hiddenParentA
        let seasonTwo = SchemaV2_7_3.AnimeEntry(
            name: "Frieren Season 2",
            type: .season(seasonNumber: 2, parentSeriesID: 209867),
            tmdbID: 407972,
            dateSaved: referenceDate(year: 2026, month: 5, day: 4)
        )
        seasonTwo.parentSeriesEntry = hiddenParentB

        let orphanParentA = SchemaV2_7_3.AnimeEntry(
            name: "Orphan Parent A",
            type: .series,
            tmdbID: 999001,
            dateSaved: referenceDate(year: 2026, month: 5, day: 5)
        )
        orphanParentA.onDisplay = false
        let orphanParentB = SchemaV2_7_3.AnimeEntry(
            name: "Orphan Parent B",
            type: .series,
            tmdbID: 999001,
            dateSaved: referenceDate(year: 2026, month: 5, day: 6)
        )
        orphanParentB.onDisplay = false

        for entry in [
            visibleSeries,
            hiddenParentA,
            hiddenParentB,
            seasonOne,
            seasonTwo,
            orphanParentA,
            orphanParentB
        ] {
            legacyContainer.mainContext.insert(entry)
        }
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)

        let migratedVisibleSeries = try #require(
            migratedEntries.first(where: { $0.tmdbID == 209867 && $0.type == .series && $0.onDisplay })
        )
        let migratedSeasons = migratedEntries.filter {
            guard case .season(_, let parentSeriesID) = $0.type else { return false }
            return parentSeriesID == 209867
        }

        #expect(migratedEntries.count == 3)
        #expect(migratedEntries.contains(where: { $0.tmdbID == 209867 && !$0.onDisplay }) == false)
        #expect(migratedEntries.contains(where: { $0.tmdbID == 999001 }) == false)
        #expect(migratedSeasons.count == 2)
        #expect(migratedSeasons.allSatisfy { $0.parentSeriesEntry?.id == migratedVisibleSeries.id })
    }

    @Test @MainActor func detailAndScoreMigrationFromV273PreservesJobs() throws {
        let storeURL = temporaryStoreURL(name: "detail-and-score-migration-v273")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_3.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)

        let legacyDetail = SchemaV2_7_3.AnimeEntryDetail(
            language: "ja-JP",
            title: "Legacy 2.7.3 Detail",
            characters: [
                SchemaV2_7_3.AnimeEntryCharacter(
                    id: 20,
                    characterName: "Second",
                    actorName: "Actor B",
                    displayOrder: 1
                ),
                SchemaV2_7_3.AnimeEntryCharacter(
                    id: 10,
                    characterName: "First",
                    actorName: "Actor A",
                    displayOrder: 0
                )
            ],
            staff: [
                SchemaV2_7_3.AnimeEntryStaff(
                    id: 300,
                    name: "Creator",
                    role: "Directing",
                    department: "Directing",
                    jobs: [
                        SchemaV2_7_3.AnimeEntryStaffJob(
                            creditID: "music",
                            job: "Music",
                            episodeCount: 8,
                            displayOrder: 1
                        ),
                        SchemaV2_7_3.AnimeEntryStaffJob(
                            creditID: "director",
                            job: "Director",
                            episodeCount: 12,
                            displayOrder: 0
                        )
                    ],
                    displayOrder: 0
                )
            ],
            seasons: [
                SchemaV2_7_3.AnimeEntrySeasonSummary(id: 2, seasonNumber: 2, title: "Season 2"),
                SchemaV2_7_3.AnimeEntrySeasonSummary(id: 1, seasonNumber: 1, title: "Season 1")
            ],
            episodes: [
                SchemaV2_7_3.AnimeEntryEpisodeSummary(
                    id: 2,
                    episodeNumber: 2,
                    title: "Episode 2",
                    displayOrder: 1
                ),
                SchemaV2_7_3.AnimeEntryEpisodeSummary(
                    id: 1,
                    episodeNumber: 1,
                    title: "Episode 1",
                    displayOrder: 0
                )
            ]
        )
        let legacyEntry = SchemaV2_7_3.AnimeEntry(
            name: "Legacy 2.7.3 Entry",
            type: .series,
            tmdbID: 700001,
            detail: legacyDetail,
            dateSaved: referenceDate(year: 2026, month: 5, day: 8),
            score: 4
        )
        legacyEntry.watchStatus = .dropped
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)
        let migratedEntry = try #require(migratedEntries.first(where: { $0.tmdbID == 700001 }))
        let migratedDetail = try #require(migratedEntry.detail)
        let migratedStaff = try #require(migratedDetail.orderedStaff.first)

        #expect(migratedEntry.score == 4)
        #expect(migratedEntry.watchStatus == .dropped)
        #expect(migratedDetail.orderedCharacters.map(\.id) == [10, 20])
        #expect(migratedDetail.seasons.map(\.seasonNumber).sorted() == [1, 2])
        #expect(migratedDetail.orderedEpisodes.map(\.id) == [1, 2])
        #expect(migratedStaff.orderedJobs.map(\.creditID) == ["director", "music"])
        #expect(migratedStaff.orderedJobs.map(\.job) == ["Director", "Music"])
    }

    @Test @MainActor func dateTrackingMigrationFromV274DefaultsToEnabled() throws {
        let storeURL = temporaryStoreURL(name: "date-tracking-migration-v274")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_4.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)

        let legacyEntry = SchemaV2_7_4.AnimeEntry(
            name: "Legacy 2.7.4 Entry",
            type: .movie,
            tmdbID: 800001,
            dateSaved: referenceDate(year: 2026, month: 5, day: 10),
            dateStarted: referenceDate(year: 2026, month: 5, day: 8),
            dateFinished: referenceDate(year: 2026, month: 5, day: 9),
            score: 3
        )
        legacyEntry.watchStatus = .watched
        legacyEntry.favorite = true
        legacyEntry.notes = "Preserve me"
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)
        let migratedEntry = try #require(migratedEntries.first(where: { $0.tmdbID == 800001 }))

        #expect(migratedEntry.watchStatus == .watched)
        #expect(migratedEntry.dateStarted == referenceDate(year: 2026, month: 5, day: 8))
        #expect(migratedEntry.dateFinished == referenceDate(year: 2026, month: 5, day: 9))
        #expect(migratedEntry.score == 3)
        #expect(migratedEntry.favorite)
        #expect(migratedEntry.notes == "Preserve me")
        #expect(migratedEntry.isDateTrackingEnabled)
    }

    @Test @MainActor func seasonEpisodeCountMigrationFromV277DefaultsToNil() throws {
        let storeURL = temporaryStoreURL(name: "season-episode-count-migration-v277")

        let legacySchema = Schema(versionedSchema: SchemaV2_7_7.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(for: legacySchema, configurations: legacyConfiguration)

        let legacyEntry = SchemaV2_7_7.AnimeEntry(
            name: "Legacy 2.7.7 Entry",
            type: .series,
            tmdbID: 900001,
            detail: SchemaV2_7_7.AnimeEntryDetail(
                language: "en-US",
                title: "Legacy Detail",
                seasons: [
                    SchemaV2_7_7.AnimeEntrySeasonSummary(
                        id: 1,
                        seasonNumber: 1,
                        title: "Season 1"
                    )
                ]
            ),
            dateSaved: referenceDate(year: 2026, month: 5, day: 11)
        )
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntries = try migratedProvider.getAllModels(ofType: AnimeEntry.self)
        let migratedEntry = try #require(migratedEntries.first(where: { $0.tmdbID == 900001 }))
        let migratedSeason = try #require(migratedEntry.detail?.seasons.first)

        #expect(migratedSeason.seasonNumber == 1)
        #expect(migratedSeason.episodeCount == nil)
    }
}

fileprivate func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}

fileprivate func temporaryStoreURL(name: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AniShelfTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory.appendingPathComponent("store.sqlite")
}
