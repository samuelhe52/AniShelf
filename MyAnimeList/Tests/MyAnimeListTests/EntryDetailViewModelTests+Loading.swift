//
//  EntryDetailViewModelTests+Loading.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension EntryDetailViewModelTests {
    @Test @MainActor func testEntryDetailUsesCachedSameLanguageDetailWhenLogoIsPresent() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let httpClient = RecordingTMDbHTTPClient { _ in
            HTTPResponse(statusCode: 500, data: Data())
        }
        let fetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTMDbResponseData: { _ in Data() }
        )
        let viewModel = EntryDetailViewModel(repository: repository, infoFetcher: fetcher)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 37,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Cached Detail",
                logoImagePath: "/logo.png"
            )
        )

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.displayTitle == "Cached Detail")
        #expect(viewModel.loadError == nil)
        #expect(await httpClient.requests.isEmpty)
    }

    @Test @MainActor func testEntryDetailRefetchesCachedSameLanguageDetailWhenLogoIsMissing() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let httpClient = RecordingTMDbHTTPClient { _ in
            HTTPResponse(statusCode: 500, data: Data())
        }
        let fetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTMDbResponseData: { _ in Data() }
        )
        let viewModel = EntryDetailViewModel(repository: repository, infoFetcher: fetcher)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 38,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Cached Detail"
            )
        )

        await viewModel.load(for: entry, language: .english)

        #expect(viewModel.displayTitle == "Cached Detail")
        #expect(viewModel.loadError != nil)
        #expect(!(await httpClient.requests).isEmpty)
    }

    @Test @MainActor func testEntryDetailRetriesSameRequestAfterFailure() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = FailingEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 39)

        await viewModel.load(for: entry, language: .english)
        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(viewModel.loadError != nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEntryDetailRestoresPersistedDetailAndRetriesAfterSaveFailure()
        async throws
    {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 40,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Persisted Detail",
                overview: "Persisted overview",
                characters: [
                    AnimeEntryCharacter(
                        id: 1,
                        characterName: "Persisted Character",
                        actorName: "Persisted Actor"
                    )
                ],
                staff: [
                    AnimeEntryStaff(
                        id: 2,
                        name: "Persisted Staff",
                        role: "Director",
                        jobs: [
                            AnimeEntryStaffJob(
                                creditID: "persisted-director",
                                job: "Director",
                                episodeCount: 12
                            )
                        ]
                    )
                ],
                seasons: [
                    AnimeEntrySeasonSummary(
                        id: 3,
                        seasonNumber: 1,
                        title: "Persisted Season"
                    )
                ],
                episodes: [
                    AnimeEntryEpisodeSummary(
                        id: 4,
                        episodeNumber: 1,
                        title: "Persisted Episode"
                    )
                ]
            )
        )
        try dataProvider.dataHandler.newEntry(entry)
        entry.notes = "Unsaved user note"

        let loader = RetryingPersistedEntryDetailLoader()
        var saveAttemptCount = 0
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            },
            detailPersistenceSaver: {
                saveAttemptCount += 1
                if saveAttemptCount == 1 {
                    throw EntryDetailPersistenceError()
                }
                try dataProvider.dataHandler.modelContext.save()
            }
        )

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 1)
        #expect(saveAttemptCount == 1)
        #expect(viewModel.loadError == "The detail could not be saved.")
        #expect(viewModel.displayTitle == "Persisted Detail")
        #expect(entry.detail?.title == "Persisted Detail")
        #expect(entry.detail?.overview == "Persisted overview")
        #expect(entry.detail?.orderedCharacters.map(\.characterName) == ["Persisted Character"])
        #expect(entry.detail?.orderedStaff.map(\.name) == ["Persisted Staff"])
        #expect(entry.detail?.orderedStaff.first?.orderedJobs.map(\.creditID) == ["persisted-director"])
        #expect(entry.detail?.seasons.map(\.title) == ["Persisted Season"])
        #expect(entry.detail?.orderedEpisodes.map(\.title) == ["Persisted Episode"])
        #expect(entry.notes == "Unsaved user note")
        #expect(!viewModel.isLoading)

        let verificationContext = ModelContext(dataProvider.sharedModelContainer)
        let persistedEntries = try verificationContext.fetch(
            FetchDescriptor<AnimeEntry>(
                predicate: #Predicate { $0.tmdbID == 40 }
            )
        )
        let persistedEntry = try #require(persistedEntries.first)
        #expect(persistedEntry.detail?.title == "Persisted Detail")
        #expect(persistedEntry.detail?.overview == "Persisted overview")
        #expect(
            persistedEntry.detail?.orderedCharacters.map(\.characterName)
                == ["Persisted Character"]
        )
        #expect(persistedEntry.detail?.orderedStaff.map(\.name) == ["Persisted Staff"])
        #expect(
            persistedEntry.detail?.orderedStaff.first?.orderedJobs.map(\.creditID)
                == ["persisted-director"]
        )
        #expect(persistedEntry.detail?.seasons.map(\.title) == ["Persisted Season"])
        #expect(persistedEntry.detail?.orderedEpisodes.map(\.title) == ["Persisted Episode"])

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(saveAttemptCount == 2)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.displayTitle == "Retried Detail")
        #expect(entry.detail?.title == "Retried Detail")
        #expect(entry.detail?.overview == "Retried overview")
        #expect(entry.detail?.orderedCharacters.map(\.characterName) == ["Retried Character"])
        #expect(entry.notes == "Unsaved user note")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEntryDetailRemovesNewDetailAfterSaveFailureAndRetries() async throws {
        let dataProvider = DataProvider(inMemory: true)
        let repository = LibraryRepository(dataProvider: dataProvider)
        let entry = AnimeEntry(name: "Movie", type: .movie, tmdbID: 41)
        try dataProvider.dataHandler.newEntry(entry)

        let loader = RetryingPersistedEntryDetailLoader()
        var saveAttemptCount = 0
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            },
            detailPersistenceSaver: {
                saveAttemptCount += 1
                if saveAttemptCount == 1 {
                    throw EntryDetailPersistenceError()
                }
                try dataProvider.dataHandler.modelContext.save()
            }
        )

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 1)
        #expect(viewModel.loadError == "The detail could not be saved.")
        #expect(entry.detail == nil)
        #expect(!viewModel.isLoading)

        let verificationContext = ModelContext(dataProvider.sharedModelContainer)
        let persistedEntries = try verificationContext.fetch(
            FetchDescriptor<AnimeEntry>(
                predicate: #Predicate { $0.tmdbID == 41 }
            )
        )
        #expect(try #require(persistedEntries.first).detail == nil)

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(saveAttemptCount == 2)
        #expect(viewModel.loadError == nil)
        #expect(viewModel.displayTitle == "Retried Detail")
        #expect(entry.detail?.title == "Retried Detail")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEntryDetailCancellationDoesNotSurfaceErrorAndAllowsRetry() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = CancellableEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 40)

        let cancelledLoad = Task {
            await viewModel.load(for: entry, language: .english)
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.displayTitle != "Cancelled Detail")

        await viewModel.load(for: entry, language: .english)

        #expect(await loader.requestCount == 2)
        #expect(viewModel.displayTitle == "Retried Detail")
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testOlderLanguageRequestCannotOverwriteNewerDetail() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = DelayedLanguageEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 41)

        let olderLoad = Task {
            await viewModel.load(for: entry, language: .japanese)
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        await viewModel.load(for: entry, language: .english)
        await olderLoad.value

        #expect(viewModel.displayTitle == "English Detail")
        #expect(entry.detail?.language == Language.english.rawValue)
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testCancelledBeforeStartDetailLoadDoesNotMutateCurrentState() async {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let loader = ImmediateLanguageEntryDetailLoader()
        let viewModel = EntryDetailViewModel(
            repository: repository,
            detailInfoLoader: { entryType, tmdbID, language in
                try await loader.load(entryType: entryType, tmdbID: tmdbID, language: language)
            }
        )
        let entry = AnimeEntry.template(id: 42)

        await viewModel.load(for: entry, language: .english)

        let cancelledLoad = Task { @MainActor in
            await viewModel.load(for: entry, language: .japanese)
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(await loader.requestCount == 1)
        #expect(viewModel.displayTitle == "English Detail")
        #expect(viewModel.loadError == nil)
        #expect(!viewModel.isLoading)
    }

    @Test func testReplaceDetailRewritesFlattenedAggregateStaffIntoPersistedJobs() throws {
        let entry = AnimeEntry.template()
        entry.detail = AnimeEntryDetail(
            language: "en-US",
            title: "Old",
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Creator",
                    role: "Director / Music",
                    department: "Directing",
                    displayOrder: 0
                )
            ]
        )

        let refreshedDTO = AnimeEntryDetailDTO(
            language: "en-US",
            title: "New",
            staff: [
                AnimeEntryStaffDTO(
                    id: 10,
                    name: "Creator",
                    role: "Directing",
                    department: "Directing",
                    jobs: [
                        AnimeEntryStaffJobDTO(
                            creditID: "director",
                            job: "Director",
                            episodeCount: 12
                        ),
                        AnimeEntryStaffJobDTO(
                            creditID: "music",
                            job: "Music",
                            episodeCount: 8
                        )
                    ]
                )
            ]
        )

        let detail = entry.replaceDetail(from: refreshedDTO)
        let staff = try #require(detail.orderedStaff.first)

        #expect(detail.title == "New")
        #expect(detail.orderedStaff.count == 1)
        #expect(staff.role == "Directing")
        #expect(staff.orderedJobs.map(\.creditID) == ["director", "music"])
        #expect(staff.orderedJobs.map(\.job) == ["Director", "Music"])
    }

}
