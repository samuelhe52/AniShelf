//
//  EntryDetailSessionTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import DataProvider
import Testing

@testable import MyAnimeList

struct EntryDetailSessionTests {
    @Test @MainActor func samePresentedEntryKeepsSessionAndScrollStateAcrossHostChanges() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let sheetSession = try #require(store.presentedSession)
        sheetSession.scrollPosition.scrollTo(y: 312)
        sheetSession.isCharacterExpanded = false
        sheetSession.presentation.activeSheet = .sharing

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let inspectorSession = try #require(store.presentedSession)

        #expect(inspectorSession === sheetSession)
        #expect(inspectorSession.scrollPosition.y == 312)
        #expect(!inspectorSession.isCharacterExpanded)
        #expect(inspectorSession.presentation.activeSheet == .sharing)
    }

    @Test @MainActor func activeEditingAndOriginalValuesSurviveHostChanges() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 84)
        entry.notes = "Saved note"
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let sheetSession = try #require(store.presentedSession)
        sheetSession.isEditingDetails = true
        sheetSession.scrollPosition.scrollTo(y: 196)
        entry.notes = "Unsaved replacement"

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let inspectorSession = try #require(store.presentedSession)

        #expect(inspectorSession === sheetSession)
        #expect(inspectorSession.isEditingDetails)
        #expect(inspectorSession.originalUserInfo.notes == "Saved note")
        #expect(inspectorSession.entry.notes == "Unsaved replacement")
        #expect(inspectorSession.scrollPosition.y == 196)
    }

    @Test @MainActor func outgoingHostCannotClearNestedPresentationsAfterMigration() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let state = LibraryEntryInteractionState()
        let session = EntryDetailSession(entry: entry, repository: repository)
        state.openDetails(for: entry)
        let sheet = try #require(state.detailHostPresentation)
        session.presentation = populatedPresentationState()

        state.transitionDetailHost(to: .inspector)
        let inspector = try #require(state.detailHostPresentation)
        session.updatePresentation(
            from: sheet.id,
            ifCurrent: { state.isCurrentDetailHostPresentation($0) },
            { presentation in
                presentation = EntryDetailPresentationState()
            }
        )

        assertPresentationIsPopulated(session.presentation)

        state.transitionDetailHost(to: .sheet)
        let replacementSheet = try #require(state.detailHostPresentation)
        session.updatePresentation(
            from: inspector.id,
            ifCurrent: { state.isCurrentDetailHostPresentation($0) },
            { presentation in
                presentation = EntryDetailPresentationState()
            }
        )

        assertPresentationIsPopulated(session.presentation)

        session.updatePresentation(
            from: replacementSheet.id,
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
        let entries = [firstEntry.syncIdentity: firstEntry, secondEntry.syncIdentity: secondEntry]
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: firstEntry.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )
        let firstSession = try #require(store.presentedSession)

        store.synchronizePresentedDetail(
            identity: secondEntry.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )
        let secondSession = try #require(store.presentedSession)

        #expect(secondSession !== firstSession)
        #expect(secondSession.entryIdentity == secondEntry.syncIdentity)

        store.synchronizePresentedDetail(
            identity: nil,
            repository: repository,
            resolveEntry: { entries[$0] }
        )
        #expect(store.presentedSession == nil)
    }

    @Test @MainActor func unresolvablePresentedEntryClearsSessionAndReportsFailure() {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )

        let didResolve = store.synchronizePresentedDetail(
            identity: AnimeEntry.template(id: 43).syncIdentity,
            repository: repository,
            resolveEntry: { _ in nil }
        )

        #expect(!didResolve)
        #expect(store.presentedSession == nil)
    }

    @Test @MainActor func previouslyResolvedEntryIsRevalidatedBeforeReusingSession() {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )

        let didResolve = store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
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
