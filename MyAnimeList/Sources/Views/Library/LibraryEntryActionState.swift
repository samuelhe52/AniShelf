//
//  LibraryEntryActionState.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

import DataProvider
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

struct LibraryEntryDetailActions {
    let open: @MainActor (AnimeEntry) -> Void
    let edit: @MainActor (AnimeEntry) -> Void
}

struct LibraryEntryPasteRequest: Identifiable, Equatable {
    let id = UUID()
    let entryIdentity: LibraryEntryIdentity
    let userInfo: UserEntryInfo
}

struct LibraryEntryWorkflowPresentation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let workflow: LibraryEntryWorkflow
}

/// Per-window entry actions both platforms share: delete and paste confirmation, and the
/// Share and Switch Poster sheets. iOS composes it into `LibraryEntryInteractionState`.
@Observable
@MainActor
final class LibraryEntryActionState {
    var deletingEntryID: LibraryEntryIdentity?
    private(set) var pendingPasteRequest: LibraryEntryPasteRequest?
    private(set) var workflowPresentation: LibraryEntryWorkflowPresentation?

    /// Runs before a workflow presents; iOS uses it to retire a pending detail edit request.
    @ObservationIgnored var willPresentWorkflow: (@MainActor () -> Void)?

    var isDeletingEntry: Bool {
        deletingEntryID != nil
    }

    func presentWorkflow(_ workflow: LibraryEntryWorkflow) {
        willPresentWorkflow?()
        workflowPresentation = LibraryEntryWorkflowPresentation(workflow: workflow)
    }

    func workflowPresentationDidDismiss(_ presentation: LibraryEntryWorkflowPresentation) {
        guard workflowPresentation?.id == presentation.id else { return }
        workflowPresentation = nil
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

extension LibraryEntryActionState {
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

    func editButton(for entry: AnimeEntry, editEntry: @escaping (AnimeEntry) -> Void) -> some View {
        Button("Edit", systemImage: "pencil") {
            editEntry(entry)
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
        editEntry: @escaping (AnimeEntry) -> Void
    ) -> some View {
        #if os(macOS)
            // A Mac menu turns a control group into a submenu, so the Mac lists each action.
            favoriteButton(for: entry, toggleFavorite: toggleFavorite)
            EntryScoreMenu(entry: entry)
            editButton(for: entry, editEntry: editEntry)
            Divider()
            shareButton(for: entry)
            EntryOpenInSubmenu(entry: entry)
            switchPosterButton(for: entry)
            savePosterButton(for: entry)
            userInfoMenu(for: entry)
            Divider()
            deleteButton(for: entry)
        #else
            ControlGroup {
                favoriteButton(for: entry, toggleFavorite: toggleFavorite)
                shareButton(for: entry)
            }
            editButton(for: entry, editEntry: editEntry)
            EntryOpenInSubmenu(entry: entry)
            switchPosterButton(for: entry)
            Divider()
            savePosterButton(for: entry)
            userInfoMenu(for: entry)
            deleteButton(for: entry)
        #endif
    }
}

#if os(macOS)
    /// A Score submenu that checks the current score; hidden while scoring is turned off.
    fileprivate struct EntryScoreMenu: View {
        let entry: AnimeEntry
        @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true

        var body: some View {
            if scoringEnabled {
                Picker(
                    "Score",
                    systemImage: "star",
                    selection: Binding(get: { entry.entryScore }, set: { entry.updateEntryScore($0) })
                ) {
                    Text("None").tag(EntryScore?.none)
                    ForEach(EntryScore.all, id: \.self) { score in
                        Text("\(score.formatted)/5").tag(Optional(score))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
#endif

extension View {
    func libraryEntryActionOverlays(
        state: LibraryEntryActionState,
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

/// The Share or Switch Poster sheet for an entry workflow.
struct LibraryEntryWorkflowSheet: View {
    let store: LibraryStore
    let presentation: LibraryEntryWorkflowPresentation

    var body: some View {
        if let entry = store.repository.existingEntry(
            identity: presentation.workflow.entryIdentity
        ) {
            switch presentation.workflow {
            case .posterSelection:
                NavigationStack {
                    PosterSelectionView(
                        tmdbID: entry.tmdbID,
                        type: entry.type,
                        originalPosterLanguageCode: entry.originalLanguageCode
                            ?? entry.parentSeriesEntry?.originalLanguageCode
                    ) { url in
                        if url != entry.posterURL || !entry.usingCustomPoster {
                            entry.updateCustomPosterURL(url)
                        }
                    }
                    .navigationTitle("Pick a poster")
                }
            case .sharing:
                AnimeSharingSheet(entry: entry)
            }
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
