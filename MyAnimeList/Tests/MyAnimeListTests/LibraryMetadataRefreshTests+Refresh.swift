//
//  LibraryMetadataRefreshTests+Refresh.swift
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

extension LibraryMetadataRefreshTests {
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

    @Test @MainActor func testMetadataRefreshSaveDoesNotEnqueueDirtyWork() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.updateDisplayState(false, at: referenceDate(year: 2026, month: 6, day: 5))
        store.repository.insert(hiddenParent)

        try await store.performWithoutSyncRecording {
            try store.repository.save()
        }

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)

        hiddenParent.name = "Frieren: Beyond Journey's End"
        try await store.performWithoutSyncRecording {
            try store.repository.save()
        }

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
    }

    @Test @MainActor func testDeferredLibrarySaveRefreshUpdatesVisibleLibraryAfterScope() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))

        try await store.performWithDeferredLibrarySaveRefresh {
            try store.repository.newEntry(
                AnimeEntry(
                    name: "Deferred Refresh",
                    type: .movie,
                    tmdbID: 500_100
                )
            )

            #expect(store.library.isEmpty)
        }

        #expect(store.library.map(\.tmdbID) == [500_100])
    }

    @Test @MainActor func testMetadataRefreshRecordsTrackingEditsMadeWhileFetching() async throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Before Refresh",
            type: .movie,
            tmdbID: 550
        )
        entry.markCreatedForLibrary(at: referenceDate(year: 2026, month: 6, day: 1))
        try store.repository.newEntry(entry)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([])
        store.rebuildSyncChangeTracking()

        let requestGate = MetadataRefreshRequestGate()
        let completion = MetadataRefreshCompletionSignal()
        let httpClient = RecordingTMDbHTTPClient { request in
            if request.url.path == "/3/movie/550" {
                await requestGate.blockRequest()
            }
            return HTTPResponse(data: libraryMetadataRefreshFixtureData(for: request.url.path))
        }
        store.infoFetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTranslationResponseData: { path in
                libraryMetadataRefreshFixtureData(for: path)
            }
        )
        let reporter = LibraryRefreshReporter { event in
            if case .refreshComplete = event {
                Task { await completion.signal() }
            }
        }

        LibraryProfileSettingsActions(store: store).refreshInfos(
            options: .init(reporter: reporter, prefetchImages: false)
        )
        await requestGate.waitForRequest()

        let editDate = referenceDate(year: 2026, month: 6, day: 2)
        entry.updateFavorite(true, at: editDate)
        try store.repository.save()

        await requestGate.release()
        for _ in 0..<100 where !(await completion.isSignaled) {
            try await Task.sleep(for: .milliseconds(10))
        }

        let queue = store.syncChangeRecorder.dirtyQueueStore.load()
        let didComplete = await completion.isSignaled
        #expect(didComplete)
        let refreshedEntry = try #require(
            store.dataProvider.getModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == 550 }
            ).first
        )
        #expect(
            refreshedEntry.detail?.orderedProductionCompanies.map(\.name) == [
                "Regency Enterprises"
            ])
        #expect(
            refreshedEntry.detail?.orderedProductionCompanies.map(\.logoPath) == [
                "/7PzJdsLGlR7oW4J0J5Xcd0pHGRg.png"
            ])
        #expect(queue.entries.count == 1)
        if case .upsert(let pendingUpsert)? = queue.entries.first {
            #expect(pendingUpsert.identity == entry.syncIdentity)
            #expect(pendingUpsert.dirtyAt == editDate)
        } else {
            #expect(Bool(false))
        }
    }

    @Test @MainActor func testRefreshInfosReportsAllFetchedEntriesSkippedWhenApplyWritesNothing()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...3).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        var completions: [LibraryRefreshCompletion] = []
        let reporter = LibraryRefreshReporter { event in
            if case .refreshComplete(let completion) = event {
                completions.append(completion)
            }
        }
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                LibraryMetadataRefreshApplyResult(
                    writtenCount: 0,
                    skippedCount: updates.count
                )
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: makeLibraryMetadataRefreshTestFetcher(),
            language: .english,
            options: .init(
                reporter: reporter,
                prefetchImages: false
            )
        )

        let completion = try #require(completions.first)
        #expect(completion.state == .completed)
        #expect(completion.successfulItemCount == 0)
        #expect(completion.failedItemCount == 0)
    }

    @Test @MainActor func testHydrateHiddenHelperParentAppliesDefaultsAndDetail() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.defaultNewEntryWatchStatus = .watching

        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.onDisplay = false
        try store.repository.newEntry(hiddenParent)

        try store.hydrateExistingEntry(
            hiddenParent,
            from: EntryMetadata(
                name: "Frieren: Beyond Journey's End",
                nameTranslations: [:],
                overview: "Elf mage travels onward.",
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 209_867,
                onAirDate: nil,
                linkToDetails: nil,
                type: .series
            ),
            detail: AnimeEntryDetailDTO(
                language: "en-US",
                title: "Frieren: Beyond Journey's End",
                runtimeMinutes: 24,
                episodeCount: 28,
                seasonCount: 1
            )
        )

        #expect(hiddenParent.onDisplay)
        #expect(hiddenParent.watchStatus == .watching)
        #expect(hiddenParent.dateStarted == nil)
        #expect(hiddenParent.detail?.runtimeMinutes == 24)
        #expect(hiddenParent.detail?.episodeCount == 28)
        #expect(hiddenParent.name == "Frieren: Beyond Journey's End")

        try store.refreshLibrary()
        #expect(store.library.map(\.tmdbID) == [209_867])
    }

    @Test @MainActor func testRefreshInfosReportsFailureForFailedChunkAndSkippedRemainderAfterSaveFailure()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...17).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        let fetcher = makeLibraryMetadataRefreshTestFetcher()
        let latestInfo = try await fetcher.latestInfo(
            entryType: .movie,
            tmdbID: 1,
            language: .english
        )
        #expect(latestInfo.0.name == "Fight Club")

        var applyCallCount = 0
        var completions: [LibraryRefreshCompletion] = []
        let reporter = LibraryRefreshReporter { event in
            if case .refreshComplete(let completion) = event {
                completions.append(completion)
            }
        }
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                applyCallCount += 1
                if applyCallCount == 2 {
                    throw TestApplyError.failed
                }
                let expectedUpdateCount = 8
                #expect(updates.count == expectedUpdateCount)
                return LibraryMetadataRefreshApplyResult(
                    writtenCount: updates.count,
                    skippedCount: 0
                )
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: fetcher,
            language: .english,
            options: .init(
                reporter: reporter,
                prefetchImages: false
            )
        )

        #expect(applyCallCount == 2)
        #expect(completions.count == 1)
        #expect(completions[0].state == .partialComplete)
        #expect(completions[0].successfulItemCount == 8)
        #expect(completions[0].failedItemCount == 9)
    }

    @Test @MainActor func testRefreshInfosDoesNotStartNextChunkBeforeCurrentChunkCompletes()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let library = (1...9).map { index in
            AnimeEntry(
                name: "Movie \(index)",
                type: .movie,
                tmdbID: index
            )
        }
        for entry in library {
            try repository.newEntry(entry)
        }

        let probe = MetadataFetchConcurrencyProbe()
        let httpClient = RecordingTMDbHTTPClient { request in
            try await probe.recordRequest(path: request.url.path)
            return HTTPResponse(data: libraryMetadataRefreshFixtureData(for: request.url.path))
        }
        let fetcher = InfoFetcher(
            client: TMDbClient(
                apiKey: "test-key",
                httpClient: httpClient,
                configuration: .default
            ),
            fetchTranslationResponseData: { path in
                try await probe.recordRequest(path: path)
                return libraryMetadataRefreshFixtureData(for: path)
            }
        )
        let refresher = LibraryMetadataRefresher(
            repository: repository,
            applyMetadataRefresh: { updates, _ in
                #expect(updates.count <= 8)
                return LibraryMetadataRefreshApplyResult(
                    writtenCount: updates.count,
                    skippedCount: 0
                )
            }
        )

        await refresher.refreshInfos(
            for: library,
            fetcher: fetcher,
            language: .english,
            options: .init(
                reporter: .silent,
                prefetchImages: false
            )
        )

        #expect(!(await probe.startedNinthMovieBeforeFirstMovieReturned))
    }
}
