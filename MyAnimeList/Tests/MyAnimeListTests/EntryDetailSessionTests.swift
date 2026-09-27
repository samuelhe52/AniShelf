//
//  EntryDetailSessionTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import DataProvider
import Foundation
import Testing

@testable import MyAnimeList

struct EntryDetailSessionTests {
    @Test @MainActor func airingSeriesRefreshesPersistedSeasonCountWithoutRepeatingTheRequest()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Series",
            type: .series,
            tmdbID: 42,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Series",
                status: "Planned",
                episodeCount: 1,
                seasons: [AnimeEntrySeasonSummary(id: 43, seasonNumber: 3, title: "Season 3", episodeCount: 1)]
            )
        )
        try repository.newEntry(entry)
        let requests = BroadcastDetailRequestCounter()
        let checker = TMDbBroadcastEligibilityChecker { _ in
            await requests.record()
            return TMDbSeriesBroadcastDetails(
                schedule: .init(
                    firstAirDate: TMDbCalendarDate(year: 2020, month: 1, day: 1),
                    nextEpisode: .init(
                        seasonNumber: 3,
                        airDate: TMDbCalendarDate(year: 2999, month: 1, day: 1)
                    ),
                    seasonAirDates: [:]
                ),
                externalIDs: .init(tvdbID: nil, imdbID: nil),
                episodeCount: 24,
                seasonEpisodeCounts: [3: 24]
            )
        }
        let resolver = TVMazeResolver(
            loadMappedShowID: { _ in nil },
            saveMappedShowID: { _, _ in .rejected },
            lookupTVDBShowID: { _ in nil },
            lookupIMDbShowID: { _ in nil },
            searchShows: { _ in [] },
            fetchShow: { _ in nil }
        )
        let session = EntryDetailSession(
            entry: entry,
            repository: repository,
            broadcastEligibilityChecker: checker,
            broadcastResolver: resolver
        )

        session.broadcast.update(
            .init(isEnabled: true, entryType: entry.type, seriesStatus: entry.detail?.status)
        )
        await session.refreshEpisodeCountsIfEligible(language: .english)
        await session.refreshEpisodeCountsIfEligible(language: .english)

        #expect(entry.episodeProgressSummary(forSeason: 3).episodeCount == 24)
        #expect(entry.detail?.episodeCount == 24)
        #expect(session.model.statCards.first(where: { $0.kind == .episodes })?.value == "24")
        #expect(await requests.count == 1)
    }

    @Test @MainActor func airingSeasonRefreshesItsProgressLimit() async throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Season 3",
            type: .season(seasonNumber: 3, parentSeriesID: 42),
            tmdbID: 43,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Season 3",
                status: "Planned",
                episodeCount: 1
            )
        )
        try repository.newEntry(entry)
        let checker = TMDbBroadcastEligibilityChecker { _ in
            TMDbSeriesBroadcastDetails(
                schedule: .init(
                    firstAirDate: TMDbCalendarDate(year: 2020, month: 1, day: 1),
                    nextEpisode: nil,
                    seasonAirDates: [3: TMDbCalendarDate(year: 2999, month: 1, day: 1)]
                ),
                externalIDs: .init(tvdbID: nil, imdbID: nil),
                seasonEpisodeCounts: [3: 24]
            )
        }
        let session = EntryDetailSession(
            entry: entry,
            repository: repository,
            broadcastEligibilityChecker: checker
        )

        await session.refreshEpisodeCountsIfEligible(language: .english)

        #expect(entry.episodeProgressSummary(forSeason: 3).episodeCount == 24)
        #expect(session.model.statCards.first(where: { $0.kind == .episodes })?.value == "24")
    }

    @Test @MainActor func ineligibleStatusSkipsTheRequestAndNetworkFailurePreservesCount()
        async throws
    {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Season",
            type: .season(seasonNumber: 3, parentSeriesID: 42),
            tmdbID: 43,
            detail: AnimeEntryDetail(
                language: Language.english.rawValue,
                title: "Season",
                status: "Ended",
                episodeCount: 1
            )
        )
        try repository.newEntry(entry)
        let requests = BroadcastDetailRequestCounter()
        let checker = TMDbBroadcastEligibilityChecker { _ in
            await requests.record()
            throw URLError(.notConnectedToInternet)
        }
        let session = EntryDetailSession(
            entry: entry,
            repository: repository,
            broadcastEligibilityChecker: checker
        )

        await session.refreshEpisodeCountsIfEligible(language: .english)
        #expect(await requests.count == 0)

        entry.detail?.status = "Returning Series"
        await session.refreshEpisodeCountsIfEligible(language: .english)
        #expect(await requests.count == 1)
        #expect(entry.episodeProgressSummary(forSeason: 3).episodeCount == 1)
    }

    @Test @MainActor func detailHostMigratesAfterNestedSheetDismissesWithoutRestoringIt() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let session = EntryDetailSession(entry: entry, repository: repository)
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        state.openDetails(for: entry)
        let inspector = try #require(state.inspectorPresentation)

        session.presentation.activeSheet = .changePoster
        session.dismissActiveSheetForHostChange()
        #expect(session.presentation.activeSheet == nil)
        #expect(session.blocksHostMigration)

        state.requestDetailHost(
            .sheet,
            migrationBlocked: session.blocksHostMigration
        )

        #expect(state.inspectorPresentation?.id == inspector.id)
        #expect(state.hasPendingDetailHostMigration)

        session.activeSheetDidDismiss()
        state.reconcileDetailHostIfPossible(
            migrationBlocked: session.blocksHostMigration
        )

        #expect(state.detailSheetPresentation != nil)
        #expect(session.presentation.activeSheet == nil)
    }

    @Test @MainActor func samePresentedEntryKeepsSessionAndScrollStateAcrossSynchronization() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        entry.notes = "Saved note"
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )
        let originalSession = try #require(store.presentedSession)
        originalSession.scrollPosition.scrollTo(y: 312)
        originalSession.isEditingDetails = true
        originalSession.isCharacterExpanded = false
        originalSession.presentation.activeSheet = .sharing
        entry.notes = "Unsaved replacement"

        store.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )
        let reusedSession = try #require(store.presentedSession)

        #expect(reusedSession === originalSession)
        #expect(reusedSession.scrollPosition.y == 312)
        #expect(reusedSession.isEditingDetails)
        #expect(reusedSession.originalUserInfo.notes == "Saved note")
        #expect(reusedSession.entry.notes == "Unsaved replacement")
        #expect(!reusedSession.isCharacterExpanded)
        #expect(reusedSession.presentation.activeSheet == .sharing)
    }

    @Test @MainActor func sheetAndInspectorMigrationsKeepTheExactPresentedSession() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        entry.notes = "Saved note"
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let store = EntryDetailSessionStore()
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let inspectorPresentation = try #require(state.inspectorPresentation)

        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )
        let originalSession = try #require(store.presentedSession)
        originalSession.scrollPosition.scrollTo(y: 312)
        originalSession.isEditingDetails = true
        originalSession.isCharacterExpanded = false
        originalSession.isStaffExpanded = true
        entry.notes = "Unsaved replacement"

        state.requestDetailHost(
            .sheet,
            migrationBlocked: false
        )
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )

        let sheetPresentation = try #require(state.detailSheetPresentation)
        let sheetSession = try #require(store.presentedSession)
        #expect(sheetPresentation.id != inspectorPresentation.id)
        #expect(sheetPresentation.detailPresentationID == canonicalPresentation.id)
        #expect(sheetSession === originalSession)

        state.requestDetailHost(
            .inspector,
            migrationBlocked: false
        )
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )

        let representedInspector = try #require(state.inspectorPresentation)
        let inspectorSession = try #require(store.presentedSession)
        #expect(representedInspector.id != inspectorPresentation.id)
        #expect(representedInspector.detailPresentationID == canonicalPresentation.id)
        #expect(inspectorSession === originalSession)
        #expect(inspectorSession.scrollPosition.y == 312)
        #expect(inspectorSession.isEditingDetails)
        #expect(!inspectorSession.isCharacterExpanded)
        #expect(inspectorSession.isStaffExpanded)
        #expect(inspectorSession.originalUserInfo.notes == "Saved note")
        #expect(inspectorSession.entry.notes == "Unsaved replacement")
        #expect(state.detailPresentation?.id == canonicalPresentation.id)
    }

    @Test @MainActor func staleHostGenerationCannotClearNestedPresentationState() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let state = LibraryEntryInteractionState()
        let session = EntryDetailSession(entry: entry, repository: repository)
        state.openDetails(for: entry)
        let firstHostPresentation = try #require(state.detailHostPresentation)
        session.presentation = populatedPresentationState()

        state.requestDetailHost(
            .inspector,
            migrationBlocked: false
        )
        let secondHostPresentation = try #require(state.detailHostPresentation)
        #expect(firstHostPresentation.id != secondHostPresentation.id)
        session.updatePresentation(
            from: firstHostPresentation.id,
            ifCurrent: { state.isCurrentDetailHostPresentation($0) },
            { presentation in
                presentation = EntryDetailPresentationState()
            }
        )

        assertPresentationIsPopulated(session.presentation)

        session.updatePresentation(
            from: secondHostPresentation.id,
            ifCurrent: { state.isCurrentDetailHostPresentation($0) },
            { presentation in
                presentation = EntryDetailPresentationState()
            }
        )

        #expect(session.presentation.activeSheet == nil)
        #expect(!session.presentation.showSeasonPicker)
        #expect(!session.presentation.showSiblingSeasonWarning)
        #expect(session.presentation.episodeProgressCompletionPrompt == nil)
        #expect(session.presentation.dateUpdateSuggestion == nil)
    }

    @Test @MainActor func changingOrClearingPresentedEntryReplacesTheSession() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let firstEntry = AnimeEntry.template(id: 1)
        let secondEntry = AnimeEntry.template(id: 2)
        let entries = [firstEntry.libraryIdentity: firstEntry, secondEntry.libraryIdentity: secondEntry]
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: firstEntry.libraryIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )
        let firstSession = try #require(store.presentedSession)

        store.synchronizePresentedDetail(
            identity: secondEntry.libraryIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )
        let secondSession = try #require(store.presentedSession)

        #expect(secondSession !== firstSession)
        #expect(secondSession.entryIdentity == secondEntry.libraryIdentity)

        store.synchronizePresentedDetail(
            identity: nil,
            repository: repository,
            resolveEntry: { entries[$0] }
        )
        #expect(store.presentedSession == nil)
    }

    @Test @MainActor func replacingResolvedEntryInstanceChangesTheSessionToken() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let originalEntry = AnimeEntry.template(id: 42)
        let replacementEntry = AnimeEntry.template(id: 42)
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: originalEntry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == originalEntry.libraryIdentity ? originalEntry : nil }
        )
        let originalSession = try #require(store.presentedSession)

        store.synchronizePresentedDetail(
            identity: replacementEntry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == replacementEntry.libraryIdentity ? replacementEntry : nil }
        )
        let replacementSession = try #require(store.presentedSession)

        #expect(replacementSession !== originalSession)
        #expect(replacementSession.entryIdentity == originalSession.entryIdentity)
        #expect(replacementSession.instanceID != originalSession.instanceID)
    }

    @Test @MainActor func previouslyResolvedEntryIsRevalidatedBeforeReusingSession() {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.libraryIdentity ? entry : nil }
        )

        let didResolve = store.synchronizePresentedDetail(
            identity: entry.libraryIdentity,
            repository: repository,
            resolveEntry: { _ in nil }
        )

        #expect(!didResolve)
        #expect(store.presentedSession == nil)
    }

    private func populatedPresentationState() -> EntryDetailPresentationState {
        EntryDetailPresentationState(
            activeSheet: .sharing,
            showSeasonPicker: true,
            showSiblingSeasonWarning: true,
            episodeProgressCompletionPrompt: .seriesWatched,
            dateUpdateSuggestion: .setFinishDateToNow
        )
    }

    private func assertPresentationIsPopulated(_ presentation: EntryDetailPresentationState) {
        #expect(presentation.activeSheet == .sharing)
        #expect(presentation.showSeasonPicker)
        #expect(presentation.showSiblingSeasonWarning)
        #expect(presentation.episodeProgressCompletionPrompt == .seriesWatched)
        #expect(presentation.dateUpdateSuggestion == .setFinishDateToNow)
    }
}

private actor BroadcastDetailRequestCounter {
    private(set) var count = 0

    func record() { count += 1 }
}
