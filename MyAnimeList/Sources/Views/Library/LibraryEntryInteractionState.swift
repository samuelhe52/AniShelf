//
//  LibraryEntryInteractionState.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/13.
//

#if !os(macOS)
    import DataProvider
    import Observation
    import SwiftUI

    struct LibraryEntryDetailHostPolicy: Equatable, Sendable {
        let host: LibraryEntryDetailHost
        let activation: LibraryEntryDetailActivation

        init(horizontalSizeClass: PlatformHorizontalSizeClass?) {
            if horizontalSizeClass == .regular {
                host = .inspector
                activation = .singleTap
            } else {
                host = .sheet
                activation = .userPreference
            }
        }
    }

    struct LibraryEntryDetailEditRequest: Equatable, Sendable {
        let id = UUID()
        let entryIdentity: LibraryEntryIdentity
        var hostPresentationID: UUID?
    }

    struct LibraryEntryDetailPresentation: Identifiable, Equatable, Sendable {
        let id = UUID()
        let entryIdentity: LibraryEntryIdentity
    }

    struct LibraryEntryDetailHostPresentation: Identifiable, Equatable, Sendable {
        let id = UUID()
        var detailPresentationID: UUID
        var entryIdentity: LibraryEntryIdentity
        let host: LibraryEntryDetailHost
        var isHostPresented = true
    }

    /// The one sheet the iOS library presents: entry detail or an entry workflow.
    enum LibraryEntrySheetRoute: Identifiable, Equatable, Sendable {
        case detail(LibraryEntryDetailHostPresentation)
        case workflow(LibraryEntryWorkflowPresentation)

        var id: UUID {
            switch self {
            case .detail(let presentation): presentation.id
            case .workflow(let presentation): presentation.id
            }
        }
    }

    /// The iOS library's entry interaction: detail presented as a sheet or an iPad inspector,
    /// the multi-selection mode, and the focused entry.
    ///
    /// The Mac inspector follows the window
    /// selection instead (`MacLibrarySelection`).
    @Observable
    @MainActor
    final class LibraryEntryInteractionState {
        let actions: LibraryEntryActionState
        var focusedEntryID: LibraryEntryIdentity?
        var isMultiSelecting: Bool = false
        var selectedEntryIDs: Set<LibraryEntryIdentity> = [] {
            didSet { LibraryBenchmarkSignposts.selectionDidChange() }
        }
        private(set) var detailEditRequest: LibraryEntryDetailEditRequest?
        private(set) var desiredDetailHost: LibraryEntryDetailHost
        private(set) var detailPresentation: LibraryEntryDetailPresentation?
        private(set) var detailHostPresentation: LibraryEntryDetailHostPresentation?
        private(set) var isInteractivelyResizing = false
        private(set) var isDetailDormantUntilInspector = false

        init(initialDetailHost: LibraryEntryDetailHost = .sheet) {
            actions = LibraryEntryActionState()
            desiredDetailHost = initialDetailHost
            // A newer workflow supersedes a pending edit without retiring the detail.
            actions.willPresentWorkflow = { [weak self] in self?.detailEditRequest = nil }
        }

        var activeSheetRoute: LibraryEntrySheetRoute? {
            if let workflowPresentation = actions.workflowPresentation {
                return .workflow(workflowPresentation)
            }
            if let detailSheetPresentation {
                return .detail(detailSheetPresentation)
            }
            return nil
        }

        var selectedEntryCount: Int {
            selectedEntryIDs.count
        }

        func focus(_ entry: AnimeEntry) {
            focusedEntryID = entry.libraryIdentity
        }

        func sheetRouteDidDismiss(_ route: LibraryEntrySheetRoute) {
            switch route {
            case .detail(let presentation):
                guard actions.workflowPresentation == nil else { return }
                detailHostDidDismiss(presentation)
            case .workflow(let presentation):
                actions.workflowPresentationDidDismiss(presentation)
            }
        }

        func enterMultiSelection() {
            isMultiSelecting = true
        }

        func exitMultiSelection() {
            isMultiSelecting = false
            selectedEntryIDs.removeAll()
        }

        func toggleSelection(for entryID: LibraryEntryIdentity) {
            if selectedEntryIDs.contains(entryID) {
                selectedEntryIDs.remove(entryID)
            } else {
                selectedEntryIDs.insert(entryID)
            }
        }

        func isSelected(_ entryID: LibraryEntryIdentity) -> Bool {
            selectedEntryIDs.contains(entryID)
        }
    }

    extension LibraryEntryInteractionState {
        var presentedDetailEntryID: LibraryEntryIdentity? {
            detailPresentation?.entryIdentity
        }

        var detailSheetPresentation: LibraryEntryDetailHostPresentation? {
            guard detailHostPresentation?.host == .sheet,
                detailHostPresentation?.isHostPresented == true
            else { return nil }
            return detailHostPresentation
        }

        var inspectorPresentation: LibraryEntryDetailHostPresentation? {
            guard detailHostPresentation?.host == .inspector,
                detailHostPresentation?.isHostPresented == true
            else { return nil }
            return detailHostPresentation
        }

        var hasPendingDetailHostMigration: Bool {
            detailPresentation != nil
                && (detailHostPresentation?.host != desiredDetailHost
                    || detailHostPresentation?.isHostPresented != true)
        }

        func openDetails(for entry: AnimeEntry) {
            isDetailDormantUntilInspector = false
            if detailEditRequest?.entryIdentity != entry.libraryIdentity {
                detailEditRequest = nil
            }
            focus(entry)
            let presentation = LibraryEntryDetailPresentation(entryIdentity: entry.libraryIdentity)
            detailPresentation = presentation

            if detailHostPresentation?.isHostPresented == true {
                detailHostPresentation?.detailPresentationID = presentation.id
                detailHostPresentation?.entryIdentity = entry.libraryIdentity
            } else {
                detailHostPresentation = LibraryEntryDetailHostPresentation(
                    detailPresentationID: presentation.id,
                    entryIdentity: entry.libraryIdentity,
                    host: desiredDetailHost
                )
            }
            retargetDetailEditRequest()
        }

        func dismissDetails() {
            detailPresentation = nil
            detailHostPresentation = nil
            detailEditRequest = nil
            isDetailDormantUntilInspector = false
        }

        func dismissDetails(ifHostPresentationID hostPresentationID: UUID) {
            guard detailHostPresentation?.id == hostPresentationID else { return }
            dismissDetails()
        }

        func requestDetailHost(
            _ host: LibraryEntryDetailHost,
            migrationBlocked: Bool,
            rootPresentationActive: Bool = false
        ) {
            desiredDetailHost = host

            if rootPresentationActive,
                host == .sheet,
                detailPresentation != nil,
                detailHostPresentation?.host == .inspector
            {
                isDetailDormantUntilInspector = true
                detailHostPresentation?.isHostPresented = false
                return
            }

            if isDetailDormantUntilInspector {
                guard host == .inspector else { return }
                isDetailDormantUntilInspector = false
            }

            guard !migrationBlocked else { return }
            guard !isInteractivelyResizing else { return }
            reconcileDetailHostPresentation()
        }

        func interactiveResizeDidChange(
            _ isResizing: Bool,
            migrationBlocked: Bool
        ) {
            isInteractivelyResizing = isResizing
            if !isResizing {
                reconcileDetailHostIfPossible(migrationBlocked: migrationBlocked)
            }
        }

        func reconcileDetailHostIfPossible(migrationBlocked: Bool) {
            guard !isInteractivelyResizing,
                !migrationBlocked,
                !isDetailDormantUntilInspector
            else { return }
            reconcileDetailHostPresentation()
        }

        func detailHostDidDismiss(_ presentation: LibraryEntryDetailHostPresentation) {
            guard detailHostPresentation?.id == presentation.id else { return }
            if isInteractivelyResizing
                || isDetailDormantUntilInspector
                || hasPendingDetailHostMigration
            {
                detailHostPresentation?.isHostPresented = false
            } else {
                dismissDetails()
            }
        }

        func isCurrentDetailHostPresentation(_ presentationID: UUID) -> Bool {
            detailHostPresentation?.id == presentationID
        }

        private func reconcileDetailHostPresentation() {
            guard let detailPresentation else {
                detailHostPresentation = nil
                return
            }

            if detailHostPresentation?.detailPresentationID == detailPresentation.id,
                detailHostPresentation?.host == desiredDetailHost,
                detailHostPresentation?.isHostPresented == true
            {
                return
            }

            detailHostPresentation = LibraryEntryDetailHostPresentation(
                detailPresentationID: detailPresentation.id,
                entryIdentity: detailPresentation.entryIdentity,
                host: desiredDetailHost
            )
            retargetDetailEditRequest()
        }

        private func retargetDetailEditRequest() {
            guard detailEditRequest?.entryIdentity == detailPresentation?.entryIdentity else { return }
            detailEditRequest?.hostPresentationID = detailHostPresentation?.id
        }

        func setEditingEntry(_ entry: AnimeEntry) {
            openDetails(for: entry)
            detailEditRequest = LibraryEntryDetailEditRequest(
                entryIdentity: entry.libraryIdentity,
                hostPresentationID: detailHostPresentation?.id
            )
        }

        func consumeDetailEditRequest(_ requestID: UUID, fromHostPresentationID: UUID) {
            guard detailEditRequest?.id == requestID,
                detailEditRequest?.hostPresentationID == fromHostPresentationID,
                detailHostPresentation?.id == fromHostPresentationID
            else { return }
            detailEditRequest = nil
        }
    }
#endif
