//
//  LibraryEntryInteractionStateTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import DataProvider
import SwiftUI
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

    @Test @MainActor func openingDetailSetsFocusAndPresentationIndependently() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.openDetails(for: entry)

        let presentation = try #require(state.detailPresentation)
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(presentation.entryIdentity == entry.syncIdentity)

        state.dismissDetails()

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == nil)
    }

    @Test @MainActor func replacingAnInspectorDetailKeepsTheInspectorHostPresented() throws {
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)

        state.openDetails(for: first)
        let firstDetailPresentation = try #require(state.detailPresentation)
        let inspectorPresentation = try #require(state.inspectorPresentation)

        state.openDetails(for: second)

        #expect(state.focusedEntryID == second.syncIdentity)
        #expect(state.presentedDetailEntryID == second.syncIdentity)
        #expect(state.detailPresentation?.id != firstDetailPresentation.id)
        #expect(state.inspectorPresentation?.id == inspectorPresentation.id)
        #expect(state.inspectorPresentation?.entryIdentity == second.syncIdentity)
        #expect(
            state.inspectorPresentation?.detailPresentationID
                == state.detailPresentation?.id
        )
    }

    @Test func galleryAlwaysUsesSheetForEveryHorizontalSizeClass() {
        let sizeClasses: [UserInterfaceSizeClass?] = [.compact, .regular, nil]

        for sizeClass in sizeClasses {
            let policy = LibraryEntryDetailHostPolicy(
                mode: .gallery,
                horizontalSizeClass: sizeClass
            )

            #expect(policy.host == .sheet)
            #expect(policy.activation == .userPreference)
        }
    }

    @Test func listAndGridUseInspectorOnlyInRegularWidth() {
        for mode in [LibraryEntryDetailMode.list, .grid] {
            let regularPolicy = LibraryEntryDetailHostPolicy(
                mode: mode,
                horizontalSizeClass: .regular
            )
            let compactPolicy = LibraryEntryDetailHostPolicy(
                mode: mode,
                horizontalSizeClass: .compact
            )
            let unspecifiedPolicy = LibraryEntryDetailHostPolicy(
                mode: mode,
                horizontalSizeClass: nil
            )

            #expect(regularPolicy.host == .inspector)
            #expect(regularPolicy.activation == .singleTap)
            #expect(compactPolicy.host == .sheet)
            #expect(compactPolicy.activation == .userPreference)
            #expect(unspecifiedPolicy.host == .sheet)
            #expect(unspecifiedPolicy.activation == .userPreference)
        }
    }

    @Test func geometricallyWidePhoneHostedCompactContextStillUsesSheet() {
        let policy = LibraryEntryDetailHostPolicy(
            mode: .grid,
            horizontalSizeClass: .compact
        )

        #expect(policy.host == .sheet)
        #expect(policy.activation == .userPreference)
    }

    @Test @MainActor func editingPresentsDetailAndRequestsTheEditingSection() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)

        state.setEditingEntry(entry)

        let request = try #require(state.detailEditRequest)
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(request.entryIdentity == entry.syncIdentity)
        #expect(state.activeWorkflow == nil)

        let hostPresentation = try #require(state.detailHostPresentation)
        #expect(request.hostPresentationID == hostPresentation.id)

        state.consumeDetailEditRequest(
            request.id,
            fromHostPresentationID: hostPresentation.id
        )

        #expect(state.detailEditRequest == nil)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
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

    @Test @MainActor func workflowPresentationsUseTypeQualifiedIdentity() throws {
        let state = LibraryEntryInteractionState()
        let movie = AnimeEntry(name: "Movie", type: .movie, tmdbID: 42)
        let series = AnimeEntry(name: "Series", type: .series, tmdbID: 42)

        state.presentWorkflow(.sharing(movie.syncIdentity))
        #expect(state.activeWorkflow == .sharing(movie.syncIdentity))

        state.presentWorkflow(.sharing(series.syncIdentity))

        let presentation = try #require(state.workflowPresentation)
        #expect(presentation.workflow == .sharing(series.syncIdentity))
        #expect(movie.syncIdentity != series.syncIdentity)
    }

    @Test @MainActor func openingAnotherEntryClearsPendingEditingIntent() {
        let state = LibraryEntryInteractionState()
        let firstEntry = AnimeEntry.template(id: 42)
        let secondEntry = AnimeEntry.template(id: 43)
        state.setEditingEntry(firstEntry)

        state.openDetails(for: secondEntry)

        #expect(state.presentedDetailEntryID == secondEntry.syncIdentity)
        #expect(state.detailEditRequest == nil)
    }

    @Test @MainActor func newerWorkflowSupersedesPendingEditWithoutRetiringDetail() {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.setEditingEntry(entry)
        let detailPresentationID = state.detailPresentation?.id

        state.presentWorkflow(.sharing(entry.syncIdentity))

        #expect(state.detailEditRequest == nil)
        #expect(state.detailPresentation?.id == detailPresentationID)
        #expect(state.activeWorkflow == .sharing(entry.syncIdentity))
    }

    @Test @MainActor func pasteConfirmationResolvesTheCurrentModelByIdentity() throws {
        let state = LibraryEntryInteractionState()
        let original = AnimeEntry.template(id: 42)
        original.notes = "Original model"
        let replacement = AnimeEntry.template(id: 42)
        replacement.notes = "Replacement model"
        let source = AnimeEntry.template(id: 99)
        source.notes = "Pasted note"

        state.preparePaste(source.userInfo, for: original)
        let request = try #require(state.pendingPasteRequest)
        state.confirmPaste(requestID: request.id) { identity in
            identity == replacement.syncIdentity ? replacement : nil
        }

        #expect(original.notes == "Original model")
        #expect(replacement.notes == "Pasted note")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func stalePasteCallbacksCannotAffectANewerRequest() throws {
        let state = LibraryEntryInteractionState()
        let first = AnimeEntry.template(id: 41)
        first.notes = "First original"
        let second = AnimeEntry.template(id: 42)
        second.notes = "Second original"
        let firstSource = AnimeEntry.template(id: 91)
        firstSource.notes = "First pasted"
        let secondSource = AnimeEntry.template(id: 92)
        secondSource.notes = "Second pasted"

        state.preparePaste(firstSource.userInfo, for: first)
        let firstRequest = try #require(state.pendingPasteRequest)
        state.preparePaste(secondSource.userInfo, for: second)
        let secondRequest = try #require(state.pendingPasteRequest)
        var staleConfirmationResolved = false

        state.confirmPaste(requestID: firstRequest.id) { _ in
            staleConfirmationResolved = true
            return second
        }
        state.clearPasteRequest(requestID: firstRequest.id)

        #expect(!staleConfirmationResolved)
        #expect(state.pendingPasteRequest?.id == secondRequest.id)
        #expect(second.notes == "Second original")

        state.confirmPaste(requestID: secondRequest.id) { _ in second }

        #expect(second.notes == "Second pasted")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func unresolvedPasteConfirmationClearsTheRequest() throws {
        let state = LibraryEntryInteractionState()
        let target = AnimeEntry.template(id: 42)
        target.notes = "Existing note"
        let source = AnimeEntry.template(id: 99)
        source.notes = "Pasted note"
        state.preparePaste(source.userInfo, for: target)
        let request = try #require(state.pendingPasteRequest)

        state.confirmPaste(requestID: request.id) { _ in nil }

        #expect(target.notes == "Existing note")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func pasteIntoEmptyEntryAppliesImmediatelyWithoutARequest() {
        let state = LibraryEntryInteractionState()
        let target = AnimeEntry.template(id: 42)
        let source = AnimeEntry.template(id: 99)
        source.notes = "Pasted note"

        state.preparePaste(source.userInfo, for: target)

        #expect(target.notes == "Pasted note")
        #expect(state.pendingPasteRequest == nil)
    }

    @Test @MainActor func interactiveResizeDefersMigrationUntilResizeEnds() throws {
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let inspectorPresentation = try #require(state.inspectorPresentation)

        state.interactiveResizeDidChange(true, migrationBlocked: false)
        state.requestDetailHost(
            .sheet,
            source: .horizontalSizeClass,
            migrationBlocked: false
        )

        #expect(state.isInteractivelyResizing)
        #expect(state.desiredDetailHost == .sheet)
        #expect(state.detailHostPresentation?.id == inspectorPresentation.id)
        #expect(state.inspectorPresentation?.id == inspectorPresentation.id)
        #expect(state.hasPendingDetailHostMigration)
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.detailPresentation?.id == canonicalPresentation.id)

        state.interactiveResizeDidChange(false, migrationBlocked: false)

        let sheetPresentation = try #require(state.detailSheetPresentation)
        #expect(!state.isInteractivelyResizing)
        #expect(sheetPresentation.id != inspectorPresentation.id)
        #expect(sheetPresentation.detailPresentationID == canonicalPresentation.id)
        #expect(!state.hasPendingDetailHostMigration)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.detailPresentation?.id == canonicalPresentation.id)
    }

    @Test @MainActor func safeDisplayModeChangeMigratesImmediatelyDuringInteractiveResize() throws {
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let inspectorPresentation = try #require(state.inspectorPresentation)

        state.interactiveResizeDidChange(true, migrationBlocked: false)
        state.requestDetailHost(
            .sheet,
            source: .displayMode,
            migrationBlocked: false
        )

        let sheetPresentation = try #require(state.detailSheetPresentation)
        #expect(state.isInteractivelyResizing)
        #expect(sheetPresentation.id != inspectorPresentation.id)
        #expect(sheetPresentation.detailPresentationID == canonicalPresentation.id)
        #expect(state.detailPresentation?.id == canonicalPresentation.id)
        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func blockedMigrationWaitsUntilNestedPresentationEnds() throws {
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let inspectorPresentation = try #require(state.inspectorPresentation)

        state.requestDetailHost(
            .sheet,
            source: .displayMode,
            migrationBlocked: true
        )

        #expect(state.desiredDetailHost == .sheet)
        #expect(state.inspectorPresentation?.id == inspectorPresentation.id)
        #expect(state.hasPendingDetailHostMigration)
        #expect(state.detailPresentation?.id == canonicalPresentation.id)

        state.reconcileDetailHostIfPossible(migrationBlocked: true)
        #expect(state.inspectorPresentation?.id == inspectorPresentation.id)

        state.reconcileDetailHostIfPossible(migrationBlocked: false)

        let sheetPresentation = try #require(state.detailSheetPresentation)
        #expect(sheetPresentation.id != inspectorPresentation.id)
        #expect(sheetPresentation.detailPresentationID == canonicalPresentation.id)
        #expect(!state.hasPendingDetailHostMigration)
    }

    @Test @MainActor func sheetAndInspectorMigrationsPreserveCanonicalDetailRoute() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let firstSheet = try #require(state.detailSheetPresentation)

        state.requestDetailHost(
            .inspector,
            source: .displayMode,
            migrationBlocked: false
        )
        let inspector = try #require(state.inspectorPresentation)
        state.requestDetailHost(
            .sheet,
            source: .displayMode,
            migrationBlocked: false
        )
        let secondSheet = try #require(state.detailSheetPresentation)

        #expect(firstSheet.id != inspector.id)
        #expect(inspector.id != secondSheet.id)
        #expect(firstSheet.id != secondSheet.id)
        #expect(firstSheet.detailPresentationID == canonicalPresentation.id)
        #expect(inspector.detailPresentationID == canonicalPresentation.id)
        #expect(secondSheet.detailPresentationID == canonicalPresentation.id)
        #expect(state.detailPresentation?.id == canonicalPresentation.id)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.focusedEntryID == entry.syncIdentity)
    }

    @Test @MainActor func staleHostDismissalAndEditCallbacksCannotAffectMigratedHost() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.setEditingEntry(entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let sheetPresentation = try #require(state.detailSheetPresentation)
        let editRequest = try #require(state.detailEditRequest)

        state.requestDetailHost(
            .inspector,
            source: .displayMode,
            migrationBlocked: false
        )
        let inspectorPresentation = try #require(state.inspectorPresentation)
        let migratedEditRequest = try #require(state.detailEditRequest)

        state.detailHostDidDismiss(sheetPresentation)
        state.consumeDetailEditRequest(
            editRequest.id,
            fromHostPresentationID: sheetPresentation.id
        )

        #expect(state.detailPresentation?.id == canonicalPresentation.id)
        #expect(state.inspectorPresentation?.id == inspectorPresentation.id)
        #expect(migratedEditRequest.id == editRequest.id)
        #expect(state.detailEditRequest?.hostPresentationID == inspectorPresentation.id)

        state.consumeDetailEditRequest(
            editRequest.id,
            fromHostPresentationID: inspectorPresentation.id
        )

        #expect(state.detailEditRequest == nil)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
    }

    @Test @MainActor func currentHostDismissalClearsCanonicalDetailAndPreservesFocus() throws {
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let inspectorPresentation = try #require(state.inspectorPresentation)

        state.detailHostDidDismiss(inspectorPresentation)

        #expect(state.focusedEntryID == entry.syncIdentity)
        #expect(state.presentedDetailEntryID == nil)
        #expect(state.detailPresentation == nil)
        #expect(state.detailHostPresentation == nil)
    }

    @Test @MainActor func interactiveHostSuppressionPreservesAndRepresentsCanonicalDetail() throws {
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let canonicalPresentation = try #require(state.detailPresentation)
        let firstInspector = try #require(state.inspectorPresentation)

        state.interactiveResizeDidChange(true, migrationBlocked: false)
        state.detailHostDidDismiss(firstInspector)

        #expect(state.detailPresentation?.id == canonicalPresentation.id)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(state.inspectorPresentation == nil)
        #expect(state.detailHostPresentation?.isHostPresented == false)
        #expect(state.hasPendingDetailHostMigration)

        state.interactiveResizeDidChange(false, migrationBlocked: false)

        let representedInspector = try #require(state.inspectorPresentation)
        #expect(representedInspector.id != firstInspector.id)
        #expect(representedInspector.detailPresentationID == canonicalPresentation.id)
        #expect(state.detailPresentation?.id == canonicalPresentation.id)
        #expect(state.presentedDetailEntryID == entry.syncIdentity)
        #expect(!state.hasPendingDetailHostMigration)
    }

    @Test @MainActor func staleWorkflowDismissalCannotCloseAReopenedWorkflow() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        let workflow = LibraryEntryWorkflow.sharing(entry.syncIdentity)
        state.presentWorkflow(workflow)
        let firstPresentation = try #require(state.workflowPresentation)
        state.workflowPresentationDidDismiss(firstPresentation)

        state.presentWorkflow(workflow)
        let secondPresentation = try #require(state.workflowPresentation)
        state.workflowPresentationDidDismiss(firstPresentation)

        #expect(firstPresentation.id != secondPresentation.id)
        #expect(state.workflowPresentation?.id == secondPresentation.id)
        #expect(state.activeWorkflow == workflow)
    }

    @Test @MainActor func workflowDoesNotRetirePresentedDetail() throws {
        let state = LibraryEntryInteractionState()
        let entry = AnimeEntry.template(id: 42)
        state.openDetails(for: entry)
        let detailPresentation = try #require(state.detailPresentation)

        state.presentWorkflow(.sharing(entry.syncIdentity))

        #expect(state.detailPresentation?.id == detailPresentation.id)
        #expect(state.workflowPresentation?.workflow == .sharing(entry.syncIdentity))
    }

    @Test func detailActivationRespectsLayoutAndUserPreference() {
        #expect(!LibraryEntryDetailActivation.userPreference.usesSingleTap(userPreference: false))
        #expect(LibraryEntryDetailActivation.userPreference.usesSingleTap(userPreference: true))
        #expect(LibraryEntryDetailActivation.singleTap.usesSingleTap(userPreference: false))
        #expect(LibraryEntryDetailActivation.singleTap.usesSingleTap(userPreference: true))
    }

    @Test @MainActor func switchingDetailEntriesKeepsPresentationWhileSessionCatchesUp() {
        let repository = LibraryRepository(dataProvider: DataProvider(inMemory: true))
        let state = LibraryEntryInteractionState(initialDetailHost: .inspector)
        let sessionStore = EntryDetailSessionStore()
        let first = AnimeEntry.template(id: 42)
        let second = AnimeEntry.template(id: 43)
        let entries = [first.syncIdentity: first, second.syncIdentity: second]

        state.openDetails(for: first)
        let inspectorPresentation = state.inspectorPresentation
        sessionStore.synchronizePresentedDetail(
            identity: first.syncIdentity,
            repository: repository,
            resolveEntry: { entries[$0] }
        )

        state.openDetails(for: second)

        #expect(state.isPresentingDetail)
        #expect(state.inspectorPresentation?.id == inspectorPresentation?.id)
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
