//
//  LibraryEntryInteractionState.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/13.
//

import DataProvider
import LibrarySync
import Observation
import SwiftUI

enum LibraryEntryWorkflow: Equatable, Sendable {
    case posterSelection(LibraryEntryIdentity)
    case sharing(LibraryEntryIdentity)

    var entryIdentity: LibraryEntryIdentity {
        switch self {
        case .posterSelection(let identity),
            .sharing(let identity):
            identity
        }
    }
}

enum LibraryEntryDetailHost: Equatable, Sendable {
    case sheet
    case inspector

    var pageBackground: Color {
        switch self {
        case .sheet:
            Color.platformSystemGroupedBackground
        case .inspector:
            Color.platformSystemBackground
        }
    }
}

struct LibraryEntryDetailActions {
    let open: @MainActor (AnimeEntry) -> Void
    let edit: @MainActor (AnimeEntry) -> Void
}

#if !os(macOS)
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
#endif

struct LibraryEntryPasteRequest: Identifiable, Equatable {
    let id = UUID()
    let entryIdentity: LibraryEntryIdentity
    let userInfo: UserEntryInfo
}

#if !os(macOS)
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
#endif

struct LibraryEntryWorkflowPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let workflow: LibraryEntryWorkflow
}

enum LibraryEntrySheetRoute: Identifiable, Equatable, Sendable {
    #if !os(macOS)
        case detail(LibraryEntryDetailHostPresentation)
    #endif
    case workflow(LibraryEntryWorkflowPresentation)

    var id: UUID {
        switch self {
        #if !os(macOS)
            case .detail(let presentation): presentation.id
        #endif
        case .workflow(let presentation): presentation.id
        }
    }
}

@Observable
@MainActor
final class LibraryEntryInteractionState {
    var focusedEntryID: LibraryEntryIdentity?
    var deletingEntryID: LibraryEntryIdentity?
    private(set) var pendingPasteRequest: LibraryEntryPasteRequest?
    var isMultiSelecting: Bool = false
    var selectedEntryIDs: Set<LibraryEntryIdentity> = []
    private(set) var workflowPresentation: LibraryEntryWorkflowPresentation?

    #if !os(macOS)
        // iOS presents entry detail as a sheet or an iPad inspector. The Mac inspector
        // follows the window selection instead (`MacLibrarySelection`).
        private(set) var detailEditRequest: LibraryEntryDetailEditRequest?
        private(set) var desiredDetailHost: LibraryEntryDetailHost
        private(set) var detailPresentation: LibraryEntryDetailPresentation?
        private(set) var detailHostPresentation: LibraryEntryDetailHostPresentation?
        private(set) var isInteractivelyResizing = false
        private(set) var isDetailDormantUntilInspector = false

        init(initialDetailHost: LibraryEntryDetailHost = .sheet) {
            desiredDetailHost = initialDetailHost
        }
    #endif

    var activeSheetRoute: LibraryEntrySheetRoute? {
        if let workflowPresentation {
            return .workflow(workflowPresentation)
        }
        #if !os(macOS)
            if let detailSheetPresentation {
                return .detail(detailSheetPresentation)
            }
        #endif
        return nil
    }

    var selectedEntryCount: Int {
        selectedEntryIDs.count
    }

    var isDeletingEntry: Bool {
        deletingEntryID != nil
    }

    func focus(_ entry: AnimeEntry) {
        focusedEntryID = entry.libraryIdentity
    }

    func sheetRouteDidDismiss(_ route: LibraryEntrySheetRoute) {
        switch route {
        #if !os(macOS)
            case .detail(let presentation):
                guard workflowPresentation == nil else { return }
                detailHostDidDismiss(presentation)
        #endif
        case .workflow(let presentation):
            workflowPresentationDidDismiss(presentation)
        }
    }

    func presentWorkflow(_ workflow: LibraryEntryWorkflow) {
        #if !os(macOS)
            detailEditRequest = nil
        #endif
        workflowPresentation = LibraryEntryWorkflowPresentation(workflow: workflow)
    }

    func workflowPresentationDidDismiss(_ presentation: LibraryEntryWorkflowPresentation) {
        guard workflowPresentation?.id == presentation.id else { return }
        workflowPresentation = nil
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

    func prepareDeletion(for entry: AnimeEntry) {
        deletingEntryID = entry.libraryIdentity
    }

    func confirmDeletion(
        resolveEntry: (LibraryEntryIdentity) -> AnimeEntry?,
        deleteEntry: (AnimeEntry) -> Void
    ) {
        guard let identity = deletingEntryID,
            let entry = resolveEntry(identity)
        else { return }

        clearDeletionRequest()
        deleteEntry(entry)
    }

    func clearDeletionRequest() {
        deletingEntryID = nil
    }

    func pasteInfo(for entry: AnimeEntry) {
        guard let pasted = UserEntryInfo.fromPasteboard() else {
            ToastCenter.global.completionState = .init(
                state: .failed,
                messageResource: "No info found on pasteboard."
            )
            return
        }
        preparePaste(pasted, for: entry)
    }

    func preparePaste(_ userInfo: UserEntryInfo, for entry: AnimeEntry) {
        if entry.userInfo.isEmpty {
            entry.updateUserInfoFromUserAction(userInfo)
            ToastCenter.global.pasted = true
        } else {
            pendingPasteRequest = LibraryEntryPasteRequest(
                entryIdentity: entry.libraryIdentity,
                userInfo: userInfo
            )
        }
    }

    func confirmPaste(
        requestID: UUID,
        resolveEntry: (LibraryEntryIdentity) -> AnimeEntry?
    ) {
        guard let request = pendingPasteRequest,
            request.id == requestID
        else { return }

        pendingPasteRequest = nil
        guard let entry = resolveEntry(request.entryIdentity) else { return }
        entry.updateUserInfoFromUserAction(request.userInfo)
        ToastCenter.global.pasted = true
    }

    func clearPasteRequest(requestID: UUID) {
        guard pendingPasteRequest?.id == requestID else { return }
        pendingPasteRequest = nil
    }
}

#if !os(macOS)
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

enum LibraryEntryDetailActivation: Equatable, Sendable {
    case userPreference
    case singleTap

    func usesSingleTap(userPreference: Bool) -> Bool {
        self == .singleTap || userPreference
    }
}

fileprivate struct LibraryEntryDetailActivationKey: EnvironmentKey {
    static let defaultValue = LibraryEntryDetailActivation.userPreference
}

extension EnvironmentValues {
    var libraryEntryDetailActivation: LibraryEntryDetailActivation {
        get { self[LibraryEntryDetailActivationKey.self] }
        set { self[LibraryEntryDetailActivationKey.self] = newValue }
    }
}

extension LibraryEntryInteractionState {
    func favoriteButton(for entry: AnimeEntry, toggleFavorite: @escaping (AnimeEntry) -> Void) -> some View {
        EntryFavoriteButton(favorited: entry.favorite) {
            toggleFavorite(entry)
            if entry.favorite {
                ToastCenter.global.favorited = true
            } else {
                ToastCenter.global.unFavorited = true
            }
        }
    }

    func shareButton(for entry: AnimeEntry) -> some View {
        Button("Share", systemImage: "square.and.arrow.up") {
            self.presentWorkflow(.sharing(entry.libraryIdentity))
        }
    }

    func editButton(
        for entry: AnimeEntry,
        editEntry: ((AnimeEntry) -> Void)? = nil
    ) -> some View {
        Button("Edit", systemImage: "pencil") {
            if let editEntry {
                editEntry(entry)
                return
            }
            #if !os(macOS)
                self.setEditingEntry(entry)
            #endif
        }
    }

    func switchPosterButton(for entry: AnimeEntry) -> some View {
        Button("Switch Poster", systemImage: "photo.badge.magnifyingglass") {
            self.presentWorkflow(.posterSelection(entry.libraryIdentity))
        }
    }

    @ViewBuilder
    func savePosterButton(for entry: AnimeEntry) -> some View {
        if let posterURL = entry.posterURL {
            SavePosterButton(posterURL: posterURL)
        }
    }

    func userInfoMenu(for entry: AnimeEntry) -> some View {
        Menu("User Info", systemImage: "person.crop.circle") {
            Button("Copy Info", systemImage: "doc.on.doc") {
                entry.userInfo.copyToPasteboard()
                ToastCenter.global.copied = true
            }
            Button("Paste Info", systemImage: "doc.on.clipboard") {
                self.pasteInfo(for: entry)
            }
            .disabled(
                !UserEntryInfo.hasPasteboardContent
            )
        }
    }

    func deleteButton(for entry: AnimeEntry) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            self.prepareDeletion(for: entry)
        }
    }

    @ViewBuilder
    func contextMenu(
        for entry: AnimeEntry,
        toggleFavorite: @escaping (AnimeEntry) -> Void,
        editEntry: ((AnimeEntry) -> Void)? = nil
    ) -> some View {
        ControlGroup {
            favoriteButton(for: entry, toggleFavorite: toggleFavorite)
            shareButton(for: entry)
        }
        editButton(for: entry, editEntry: editEntry)
        switchPosterButton(for: entry)
        Divider()
        savePosterButton(for: entry)
        userInfoMenu(for: entry)
        deleteButton(for: entry)
    }
}

extension View {
    func libraryEntryInteractionOverlays(
        state: LibraryEntryInteractionState,
        deleteEntry: @escaping (AnimeEntry) -> Void,
        resolveEntry: @escaping (LibraryEntryIdentity) -> AnimeEntry?
    ) -> some View {
        let presentedPasteRequest = state.pendingPasteRequest

        return
            self
            .alert(
                "Delete Anime?",
                isPresented: Binding(
                    get: { state.isDeletingEntry },
                    set: {
                        if !$0 {
                            state.clearDeletionRequest()
                        }
                    }
                ),
                presenting: state.deletingEntryID.flatMap(resolveEntry)
            ) { _ in
                Button("Delete", role: .destructive) {
                    state.confirmDeletion(
                        resolveEntry: resolveEntry,
                        deleteEntry: deleteEntry
                    )
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Paste Info?",
                isPresented: Binding(
                    get: {
                        guard let requestID = presentedPasteRequest?.id else { return false }
                        return state.pendingPasteRequest?.id == requestID
                    },
                    set: { isPresented in
                        guard !isPresented,
                            let requestID = presentedPasteRequest?.id
                        else { return }
                        state.clearPasteRequest(requestID: requestID)
                    }
                ),
                presenting: presentedPasteRequest
            ) { request in
                Button("Paste", role: .destructive) {
                    state.confirmPaste(
                        requestID: request.id,
                        resolveEntry: resolveEntry
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This anime already has edits. Pasting will overwrite current info.")
            }
    }
}

fileprivate struct SavePosterButton: View {
    let posterURL: URL
    @Environment(\.windowSceneIdentifier) private var windowSceneIdentifier

    var body: some View {
        #if os(macOS)
            // The Mac share menu cannot save a file, so download it into a save panel.
            Button("Save Poster…", systemImage: "photo.badge.arrow.down") {
                ShareSheetPresenter.saveDownload(of: posterURL, sceneIdentifier: windowSceneIdentifier)
            }
        #else
            ShareLink(item: posterURL) {
                Label("Save Poster", systemImage: "photo.badge.arrow.down")
            }
        #endif
    }
}
