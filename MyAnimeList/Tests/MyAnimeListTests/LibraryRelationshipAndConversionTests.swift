//
//  LibraryRelationshipAndConversionTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct LibraryRelationshipAndConversionTests {
    let fetcher = InfoFetcher()

    @MainActor let dataProviderForPreview = DataProvider.forPreview

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

    @Test @MainActor func testExistingEntryByIdentityIgnoresDifferentTypesWithSameTMDbID() throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)

        let seriesEntry = AnimeEntry(
            name: "Series Duplicate",
            type: .series,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1)
        )
        try repository.newEntry(seriesEntry)

        let movieEntry = AnimeEntry(
            name: "Movie Duplicate",
            type: .movie,
            tmdbID: 209867,
            dateSaved: referenceDate(year: 2026, month: 5, day: 2)
        )
        try repository.newEntry(movieEntry)

        let resolvedEntry = try #require(repository.existingEntry(identity: seriesEntry.syncIdentity))
        #expect(resolvedEntry.id == seriesEntry.id)
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
            fetcher: fetcher,
            latestInfoFetcher: makeLatestInfoFetcher()
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
            fetcher: fetcher,
            latestInfoFetcher: makeLatestInfoFetcher()
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
}

private func makeLatestInfoFetcher() -> LibraryEntryLatestInfoFetcher {
    { entryType, tmdbID, _ in
        switch entryType {
        case .series:
            return (
                EntryMetadata(
                    name: "Frieren",
                    nameTranslations: [:],
                    overview: nil,
                    overviewTranslations: [:],
                    posterURL: nil,
                    backdropURL: nil,
                    logoURL: nil,
                    tmdbID: tmdbID,
                    onAirDate: nil,
                    linkToDetails: nil,
                    type: .series
                ),
                AnimeEntryDetailDTO(language: "en-US", title: "Frieren")
            )
        case .season(let seasonNumber, let parentSeriesID):
            return (
                EntryMetadata(
                    name: "Frieren Season \(seasonNumber)",
                    nameTranslations: [:],
                    overview: nil,
                    overviewTranslations: [:],
                    posterURL: nil,
                    backdropURL: nil,
                    logoURL: nil,
                    tmdbID: tmdbID,
                    onAirDate: nil,
                    linkToDetails: nil,
                    type: .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID)
                ),
                AnimeEntryDetailDTO(language: "en-US", title: "Frieren Season \(seasonNumber)")
            )
        case .movie:
            fatalError("Unexpected movie conversion fetch in LibraryRelationshipAndConversionTests")
        }
    }
}
