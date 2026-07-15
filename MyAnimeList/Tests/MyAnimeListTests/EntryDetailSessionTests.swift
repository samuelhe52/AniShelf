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
    @Test @MainActor func samePresentedEntryKeepsSessionAndScrollStateAcrossSynchronization() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let originalSession = try #require(store.presentedSession)
        originalSession.scrollPosition.scrollTo(y: 312)
        originalSession.isCharacterExpanded = false
        originalSession.presentation.activeSheet = .sharing

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let reusedSession = try #require(store.presentedSession)

        #expect(reusedSession === originalSession)
        #expect(reusedSession.scrollPosition.y == 312)
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
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let originalSession = try #require(store.presentedSession)
        originalSession.scrollPosition.scrollTo(y: 312)
        originalSession.isEditingDetails = true
        originalSession.isCharacterExpanded = false
        originalSession.isStaffExpanded = true
        entry.notes = "Unsaved replacement"

        state.requestDetailHost(
            .sheet,
            source: .displayMode,
            migrationBlocked: false
        )
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )

        let sheetPresentation = try #require(state.detailSheetPresentation)
        let sheetSession = try #require(store.presentedSession)
        #expect(sheetPresentation.id != inspectorPresentation.id)
        #expect(sheetPresentation.detailPresentationID == canonicalPresentation.id)
        #expect(sheetSession === originalSession)

        state.requestDetailHost(
            .inspector,
            source: .displayMode,
            migrationBlocked: false
        )
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
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

    @Test @MainActor func nestedPresentationBlocksMigrationWithoutReplacingSession() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 42)
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let store = EntryDetailSessionStore()
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let inspectorPresentation = try #require(state.inspectorPresentation)
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let originalSession = try #require(store.presentedSession)
        originalSession.presentation.activeSheet = .sharing

        state.requestDetailHost(
            .sheet,
            source: .displayMode,
            migrationBlocked: originalSession.blocksHostMigration
        )
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )

        let blockedSession = try #require(store.presentedSession)
        #expect(blockedSession === originalSession)
        #expect(blockedSession.presentation.activeSheet == .sharing)
        #expect(state.inspectorPresentation?.id == inspectorPresentation.id)
        #expect(state.hasPendingDetailHostMigration)

        originalSession.presentation.activeSheet = nil
        state.reconcileDetailHostIfPossible(
            migrationBlocked: originalSession.blocksHostMigration
        )
        store.synchronizePresentedDetail(
            identity: state.presentedDetailEntryID,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )

        let sheetPresentation = try #require(state.detailSheetPresentation)
        let migratedSession = try #require(store.presentedSession)
        #expect(sheetPresentation.detailPresentationID == canonicalPresentation.id)
        #expect(migratedSession === originalSession)
        #expect(migratedSession.presentation.activeSheet == nil)
        #expect(!state.hasPendingDetailHostMigration)
    }

    @Test @MainActor func activeEditingAndOriginalValuesSurviveSynchronization() throws {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 84)
        entry.notes = "Saved note"
        let store = EntryDetailSessionStore()

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let originalSession = try #require(store.presentedSession)
        originalSession.isEditingDetails = true
        originalSession.scrollPosition.scrollTo(y: 196)
        entry.notes = "Unsaved replacement"

        store.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: repository,
            resolveEntry: { $0 == entry.syncIdentity ? entry : nil }
        )
        let reusedSession = try #require(store.presentedSession)

        #expect(reusedSession === originalSession)
        #expect(reusedSession.isEditingDetails)
        #expect(reusedSession.originalUserInfo.notes == "Saved note")
        #expect(reusedSession.entry.notes == "Unsaved replacement")
        #expect(reusedSession.scrollPosition.y == 196)
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
            source: .displayMode,
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
