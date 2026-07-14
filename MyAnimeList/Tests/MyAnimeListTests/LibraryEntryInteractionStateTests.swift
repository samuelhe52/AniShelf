//
//  LibraryEntryInteractionStateTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import CoreGraphics
import DataProvider
import Testing

@testable import MyAnimeList

struct LibraryEntryInteractionStateTests {
    @Test @MainActor func focusingDoesNotPresentDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.focus(entry)

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func openingDetailSetsFocusAndPresentationIndependently() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.openDetails(for: entry)

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)

        state.dismissDetails()

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func multiSelectionDoesNotReplaceFocusedEntry() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.focus(entry)

        state.enterMultiSelection()
        state.toggleSelection(for: 7)
        state.toggleSelection(for: 9)

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.selectedEntryIDs == [7, 9])
    }

    @Test @MainActor func workflowRoutesUseTypeQualifiedIdentity() {
        let state = LibraryEntryInteractionState()
        let movie = AnimeEntry(name: "Movie", type: .movie, tmdbID: 42)
        let series = AnimeEntry(name: "Series", type: .series, tmdbID: 42)

        state.setEditingEntry(movie)
        #expect(state.activeWorkflow == .editing(movie.syncIdentity))

        state.setEditingEntry(series)
        #expect(state.activeWorkflow == .editing(series.syncIdentity))
        #expect(movie.syncIdentity != series.syncIdentity)
    }

    @Test @MainActor func routeStateSurvivesPresentationPolicyChanges() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        state.presentWorkflow(.sharing(entry.syncIdentity))

        let policy = LibraryPresentationPolicy()
        _ = policy.evaluate(
            .init(
                availableSize: CGSize(width: 430, height: 900),
                libraryMode: .gallery
            )
        )
        _ = policy.evaluate(
            .init(
                availableSize: CGSize(width: 1_200, height: 900),
                libraryMode: .gallery
            )
        )

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.activeWorkflow == .sharing(entry.syncIdentity))
    }

    @Test @MainActor func editingRemainsAnExplicitWorkflowBesidePassiveDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)

        state.setEditingEntry(entry)

        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.activeWorkflow == .editing(entry.syncIdentity))
    }

    @Test @MainActor func sheetEditingKeepsTheDedicatedWorkflow() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.transitionDetailHost(to: .inspector)
        state.transitionDetailHost(to: .sheet)
        state.setEditingEntry(entry)

        #expect(state.presentedDetailEntryID == nil)
        #expect(state.inspectorEditRequest == nil)
        #expect(state.activeWorkflow == .editing(entry.syncIdentity))
    }

    @Test @MainActor func inspectorEditingRoutesDetailAndRequestsTheEditingSection() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.transitionDetailHost(to: .inspector)

        state.setEditingEntry(entry)

        let request = state.inspectorEditRequest
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(request?.entryIdentity == entry.syncIdentity)
        #expect(state.activeWorkflow == nil)

        if let request {
            state.consumeInspectorEditRequest(request.id)
        }
        #expect(state.inspectorEditRequest == nil)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func openingAnotherInspectorEntryClearsPendingEditingIntent() {
        let state = LibraryEntryInteractionState()
        let firstEntry = AnimeEntry.template(id: 42)
        let secondEntry = AnimeEntry.template(id: 43)
        state.transitionDetailHost(to: .inspector)
        state.setEditingEntry(firstEntry)

        state.openDetails(for: secondEntry)

        #expect(state.presentedDetailEntryID == secondEntry.syncIdentity)
        #expect(state.inspectorEditRequest == nil)

        state.openDetails(for: firstEntry)
        #expect(state.inspectorEditRequest == nil)
    }

    @Test @MainActor func pendingInspectorEditMigratesToTheSheetWorkflow() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.transitionDetailHost(to: .inspector)
        state.setEditingEntry(entry)

        state.transitionDetailHost(to: .sheet)

        #expect(state.desiredDetailHost == .sheet)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.inspectorEditRequest == nil)
        #expect(state.activeWorkflow == .editing(entry.syncIdentity))
    }

    @Test @MainActor func hostMigrationDismissalsPreserveTheCanonicalDetailRoute() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let firstSheet = try! #require(state.detailHostPresentation)

        state.transitionDetailHost(to: .inspector)
        let inspector = try! #require(state.detailHostPresentation)
        state.transitionDetailHost(to: .sheet)
        let secondSheet = try! #require(state.detailHostPresentation)

        state.detailHostDidDismiss(firstSheet)
        state.detailHostDidDismiss(inspector)

        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.desiredDetailHost == .sheet)
        #expect(secondSheet.id != firstSheet.id)
        #expect(secondSheet.detailPresentationID == firstSheet.detailPresentationID)
    }

    @Test @MainActor func genuineInspectorDismissalFromTheStableHostClosesDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.transitionDetailHost(to: .inspector)
        state.openDetails(for: entry)
        let inspector = try! #require(state.inspectorPresentation)

        state.detailHostDidDismiss(inspector)

        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func omittedHostCallbackLeavesNoDismissalDebtAfterRapidReversal() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.transitionDetailHost(to: .inspector)
        state.openDetails(for: entry)
        let firstInspector = try! #require(state.inspectorPresentation)

        state.transitionDetailHost(to: .sheet)
        let sheet = try! #require(state.detailHostPresentation)
        state.transitionDetailHost(to: .inspector)
        let secondInspector = try! #require(state.inspectorPresentation)

        state.detailHostDidDismiss(sheet)

        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.desiredDetailHost == .inspector)
        #expect(secondInspector.id != firstInspector.id)

        state.detailHostDidDismiss(secondInspector)

        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func genuineDismissalFromTheStableHostClosesDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let sheet = try! #require(state.detailHostPresentation)

        state.detailHostDidDismiss(sheet)

        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func staleHostDismissalCannotCloseAReopenedDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let firstSheet = try! #require(state.detailHostPresentation)

        state.dismissDetails()
        state.openDetails(for: entry)
        let secondSheet = try! #require(state.detailHostPresentation)
        state.detailHostDidDismiss(firstSheet)

        #expect(firstSheet.id != secondSheet.id)
        #expect(firstSheet.detailPresentationID != secondSheet.detailPresentationID)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func replacingInspectorEntryRejectsOldHostAndDetailCallbacks() {
        let state = LibraryEntryInteractionState()
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)
        state.transitionDetailHost(to: .inspector)
        state.openDetails(for: first)
        let firstInspector = try! #require(state.inspectorPresentation)

        state.openDetails(for: second)
        let secondInspector = try! #require(state.inspectorPresentation)
        state.detailHostDidDismiss(firstInspector)
        state.dismissDetails(ifPresentationID: firstInspector.detailPresentationID)

        #expect(firstInspector.id != secondInspector.id)
        #expect(firstInspector.detailPresentationID != secondInspector.detailPresentationID)
        #expect(state.presentedDetailEntryID == second.syncIdentity)
    }

    @Test @MainActor func workflowPreemptionRetiresAndRenewsThePassiveSheetHost() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let firstDetailRoute = try! #require(state.activeSheetRoute)

        state.presentWorkflow(.sharing(entry.syncIdentity))
        let workflowRoute = try! #require(state.activeSheetRoute)
        state.sheetDidDismiss(firstDetailRoute)

        #expect(state.activeSheetRoute?.id == workflowRoute.id)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)

        state.sheetDidDismiss(workflowRoute)
        let resumedDetailRoute = try! #require(state.activeSheetRoute)
        state.sheetDidDismiss(firstDetailRoute)

        #expect(resumedDetailRoute.id != firstDetailRoute.id)
        #expect(state.activeSheetRoute?.id == resumedDetailRoute.id)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func staleWorkflowDismissalCannotCloseAReopenedWorkflow() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        let workflow = LibraryEntryWorkflow.sharing(entry.syncIdentity)
        state.presentWorkflow(workflow)
        let firstRoute = try! #require(state.activeSheetRoute)
        state.sheetDidDismiss(firstRoute)

        state.presentWorkflow(workflow)
        let secondRoute = try! #require(state.activeSheetRoute)
        state.sheetDidDismiss(firstRoute)

        #expect(firstRoute.id != secondRoute.id)
        #expect(state.activeSheetRoute?.id == secondRoute.id)
        #expect(state.activeWorkflow == workflow)
    }

    @Test @MainActor func workflowRouteRemainsCanonicalWithoutEntryResolution() {
        let state = LibraryEntryInteractionState()
        let detailEntry = AnimeEntry.template(id: 42)
        let unavailableEntry = AnimeEntry.template(id: 43)
        state.openDetails(for: detailEntry)
        state.presentWorkflow(.sharing(unavailableEntry.syncIdentity))

        let route = try! #require(state.activeSheetRoute)
        #expect(route.entryIdentity == unavailableEntry.syncIdentity)
        #expect(state.presentedDetailEntryID == detailEntry.syncIdentity)
    }

    @Test @MainActor func workflowDoesNotRetireAnInspectorBehindItsSheet() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.transitionDetailHost(to: .inspector)
        state.openDetails(for: entry)
        let inspector = try! #require(state.inspectorPresentation)

        state.presentWorkflow(.sharing(entry.syncIdentity))

        #expect(state.inspectorPresentation?.id == inspector.id)
        #expect(state.activeSheetRoute?.entryIdentity == entry.syncIdentity)
    }

    @Test func inspectorActivationUsesSingleTapWithoutChangingSheetPreference() {
        let sheetActivation = LibraryEntryDetailActivation(.sheet)
        let inspectorActivation = LibraryEntryDetailActivation(.inspector)

        #expect(!sheetActivation.usesSingleTap(userPreference: false))
        #expect(sheetActivation.usesSingleTap(userPreference: true))
        #expect(inspectorActivation.usesSingleTap(userPreference: false))
        #expect(inspectorActivation.usesSingleTap(userPreference: true))
    }

    @Test @MainActor func openingAnotherEntryReplacesAnOpenInspectorSelection() {
        let state = LibraryEntryInteractionState()
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)

        state.openDetails(for: first)
        state.openDetails(for: second)

        #expect(state.focusedEntryID == second.syncIdentity)
        #expect(state.presentedDetailEntryID == second.syncIdentity)
    }

    @Test @MainActor func switchingInspectorEntriesKeepsPresentationWhileSessionCatchesUp() {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let state = LibraryEntryInteractionState()
        let sessionStore = EntryDetailSessionStore()
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)
        let entries = [first.syncIdentity: first, second.syncIdentity: second]

        state.openDetails(for: first)
        sessionStore.synchronizePresentedDetail(
            identity: first.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )

        state.openDetails(for: second)

        #expect(state.isPresentingDetail)
        #expect(sessionStore.session(for: second.syncIdentity) == nil)

        sessionStore.synchronizePresentedDetail(
            identity: second.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )

        #expect(state.isPresentingDetail)
        #expect(sessionStore.session(for: second.syncIdentity)?.entryIdentity == second.syncIdentity)
    }
}
