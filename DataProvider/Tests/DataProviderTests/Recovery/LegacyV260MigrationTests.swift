//
//  LegacyV260MigrationTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/6.
//

import Foundation
import SwiftData
import Testing

@testable import DataProvider

struct LegacyV260MigrationTests {
    @Test func recoveryAttemptUsesTheFirstSuccessfulMeasure() throws {
        var calls: [String] = []

        let result: Int = try ModelContainerLoader.load(
            primary: {
                calls.append("primary")
                throw RecoveryAttemptTestError.primary
            },
            recoveryMeasures: [
                (
                    "first",
                    {
                        calls.append("first")
                        throw RecoveryAttemptTestError.measure
                    }
                ),
                (
                    "second",
                    {
                        calls.append("second")
                        return 42
                    }
                ),
                (
                    "unused",
                    {
                        calls.append("unused")
                        return 0
                    }
                )
            ]
        )

        #expect(result == 42)
        #expect(calls == ["primary", "first", "second"])
    }

    @Test func recoveryAttemptThrowsThePrimaryErrorWhenEveryMeasureFails() {
        do {
            let _: Int = try ModelContainerLoader.load(
                primary: { throw RecoveryAttemptTestError.primary },
                recoveryMeasures: [
                    ("first", { throw RecoveryAttemptTestError.measure }),
                    ("second", { throw RecoveryAttemptTestError.measure })
                ]
            )
            Issue.record("Expected the recovery attempt to fail")
        } catch {
            #expect(error as? RecoveryAttemptTestError == .primary)
        }
    }

    @Test @MainActor func legacyV260StoreMigratesThroughCompatibilityPlan() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelfTests-legacy-v260-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let storeURL = directoryURL.appendingPathComponent("library.store")
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2024, month: 1, day: 1)
        )!
        let legacySchema = Schema(versionedSchema: SchemaV2_6_0Legacy.self)
        let legacyConfiguration = ModelConfiguration(schema: legacySchema, url: storeURL)
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            configurations: legacyConfiguration
        )
        let detail = LegacyAnimeEntryDetailPayloadV2_6_0(
            language: "en-US",
            title: "Legacy detail",
            subtitle: nil,
            overview: "Preserve this detail.",
            status: "Ended",
            airDate: date,
            primaryLinkURL: URL(string: "https://example.com/legacy")!,
            heroImageURL: URL(string: "https://image.tmdb.org/t/p/w780/heroes/legacy.jpg")!,
            logoImageURL: URL(string: "https://image.tmdb.org/t/p/w500/logos/legacy.png")!,
            genreIDs: [16],
            voteAverage: 8.5,
            runtimeMinutes: 24,
            episodeCount: 12,
            seasonCount: 1,
            characters: [
                .init(
                    id: 101,
                    characterName: "Lead",
                    actorName: "Actor",
                    profileURL: URL(string: "https://image.tmdb.org/t/p/w185/people/lead.jpg")
                )
            ],
            seasons: [
                .init(
                    id: 201,
                    seasonNumber: 1,
                    title: "Season 1",
                    posterURL: URL(string: "https://image.tmdb.org/t/p/w342/seasons/1.jpg")
                )
            ],
            episodes: [
                .init(
                    id: 301,
                    episodeNumber: 1,
                    title: "Episode 1",
                    airDate: date,
                    imageURL: URL(string: "https://image.tmdb.org/t/p/w300/episodes/1.jpg")
                )
            ]
        )
        let legacyEntry = SchemaV2_6_0Legacy.AnimeEntry(
            name: "Legacy entry",
            type: .movie,
            tmdbID: 9_001,
            detail: detail,
            dateSaved: date
        )
        legacyContainer.mainContext.insert(legacyEntry)
        try legacyContainer.mainContext.save()

        let migratedProvider = DataProvider(url: storeURL)
        let migratedEntry = try #require(
            try migratedProvider.getAllModels(ofType: AnimeEntry.self).first
        )
        let migratedDetail = try #require(migratedEntry.detail)

        #expect(migratedEntry.tmdbID == 9_001)
        #expect(migratedDetail.title == "Legacy detail")
        #expect(migratedDetail.overview == "Preserve this detail.")
        #expect(migratedDetail.logoImagePath == "/logos/legacy.png")
        #expect(migratedDetail.orderedCharacters.map(\.characterName) == ["Lead"])
        #expect(migratedDetail.seasons.map(\.title) == ["Season 1"])
        #expect(migratedDetail.orderedEpisodes.map(\.title) == ["Episode 1"])
    }
}

fileprivate enum RecoveryAttemptTestError: Error {
    case primary
    case measure
}
