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
import UIKit

enum LibraryEntryWorkflow: Identifiable, Equatable, Sendable {
    case editing(LibraryEntrySyncIdentity)
    case posterSelection(LibraryEntrySyncIdentity)
    case sharing(LibraryEntrySyncIdentity)

    var id: String {
        switch self {
        case .editing(let identity):
            "editing:\(identity.rawID)"
        case .posterSelection(let identity):
            "poster:\(identity.rawID)"
        case .sharing(let identity):
            "sharing:\(identity.rawID)"
        }
    }

    var entryIdentity: LibraryEntrySyncIdentity {
        switch self {
        case .editing(let identity),
            .posterSelection(let identity),
            .sharing(let identity):
            identity
        }
    }
}

@Observable
@MainActor
final class LibraryEntryInteractionState {
    var focusedEntryID: LibraryEntrySyncIdentity?
    var presentedDetailEntryID: LibraryEntrySyncIdentity?
    var activeWorkflow: LibraryEntryWorkflow?
    var deletingEntryID: LibraryEntrySyncIdentity?
    var showPasteAlert: Bool = false
    var pasteAction: (() -> Void)?
    var isMultiSelecting: Bool = false
    var selectedEntryIDs: Set<Int> = []
    private(set) var desiredDetailHost: LibraryEntryDetailHost = .sheet
    private var presentedDetailHosts: Set<LibraryEntryDetailHost> = []
    private var pendingHostMigrationDismissals: Set<LibraryEntryDetailHost> = []

    var selectedEntryCount: Int {
        selectedEntryIDs.count
    }

    var isDeletingEntry: Bool {
        deletingEntryID != nil
    }

    func focus(_ entry: AnimeEntry) {
        focusedEntryID = entry.syncIdentity
    }

    func focus(entryID: LibraryEntrySyncIdentity?) {
        focusedEntryID = entryID
    }

    func openDetails(for entry: AnimeEntry) {
        focus(entry)
        presentedDetailEntryID = entry.syncIdentity
    }

    func dismissDetails() {
        presentedDetailEntryID = nil
    }

    func transitionDetailHost(to host: LibraryEntryDetailHost) {
        guard desiredDetailHost != host else { return }

        if presentedDetailEntryID != nil,
            presentedDetailHosts.contains(desiredDetailHost)
        {
            pendingHostMigrationDismissals.insert(desiredDetailHost)
        }
        desiredDetailHost = host
    }

    func detailHostDidPresent(_ host: LibraryEntryDetailHost) {
        presentedDetailHosts.insert(host)
    }

    func detailHostDidDismiss(_ host: LibraryEntryDetailHost) {
        presentedDetailHosts.remove(host)

        if pendingHostMigrationDismissals.remove(host) != nil {
            return
        }

        guard desiredDetailHost == host else { return }
        dismissDetails()
    }

    func enterMultiSelection() {
        isMultiSelecting = true
    }

    func exitMultiSelection() {
        isMultiSelecting = false
        selectedEntryIDs.removeAll()
    }

    func toggleSelection(for entryID: Int) {
        if selectedEntryIDs.contains(entryID) {
            selectedEntryIDs.remove(entryID)
        } else {
            selectedEntryIDs.insert(entryID)
        }
    }

    func isSelected(_ entryID: Int) -> Bool {
        selectedEntryIDs.contains(entryID)
    }

    func selectedEntries(from entries: [AnimeEntry]) -> [AnimeEntry] {
        entries.filter { selectedEntryIDs.contains($0.tmdbID) }
    }

    func prepareDeletion(for entry: AnimeEntry) {
        deletingEntryID = entry.syncIdentity
    }

    func confirmDeletion(
        resolveEntry: (LibraryEntrySyncIdentity) -> AnimeEntry?,
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

    func setEditingEntry(_ entry: AnimeEntry) {
        activeWorkflow = .editing(entry.syncIdentity)
    }

    func pasteInfo(for entry: AnimeEntry) {
        if let pasted = UserEntryInfo.fromPasteboard() {
            let paste = {
                entry.updateUserInfoFromUserAction(pasted)
                ToastCenter.global.pasted = true
            }
            if entry.userInfo.isEmpty {
                paste()
            } else {
                showPasteAlert = true
                pasteAction = paste
            }
        } else {
            ToastCenter.global.completionState = .init(
                state: .failed,
                messageResource: "No info found on pasteboard."
            )
        }
    }

    func highlightBinding(for entry: AnimeEntry, highlightedEntryID: Binding<Int?>) -> Binding<Bool> {
        highlightBinding(for: entry.tmdbID, highlightedEntryID: highlightedEntryID)
    }

    func highlightBinding(for entryID: Int, highlightedEntryID: Binding<Int?>) -> Binding<Bool> {
        Binding(
            get: { highlightedEntryID.wrappedValue == entryID },
            set: { if !$0 { highlightedEntryID.wrappedValue = nil } }
        )
    }
}

enum LibraryEntryDetailHost: Hashable, Sendable {
    case sheet
    case inspector

    init(_ presentation: LibraryPresentationPolicy.DetailPresentation) {
        switch presentation {
        case .sheet:
            self = .sheet
        case .inspector:
            self = .inspector
        }
    }
}

enum LibraryEntryDetailActivation: Equatable, Sendable {
    case userPreference
    case singleTap

    init(_ presentation: LibraryPresentationPolicy.DetailPresentation) {
        switch presentation {
        case .sheet:
            self = .userPreference
        case .inspector:
            self = .singleTap
        }
    }

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
            self.activeWorkflow = .sharing(entry.syncIdentity)
        }
    }

    func editButton(for entry: AnimeEntry) -> some View {
        Button("Edit", systemImage: "pencil") {
            self.activeWorkflow = .editing(entry.syncIdentity)
        }
    }

    func switchPosterButton(for entry: AnimeEntry) -> some View {
        Button("Switch Poster", systemImage: "photo.badge.magnifyingglass") {
            self.activeWorkflow = .posterSelection(entry.syncIdentity)
        }
    }

    @ViewBuilder
    func savePosterButton(for entry: AnimeEntry) -> some View {
        if let posterURL = entry.posterURL {
            ShareLink(item: posterURL) {
                Label("Save Poster", systemImage: "photo.badge.arrow.down")
            }
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
                !UIPasteboard.general.contains(
                    pasteboardTypes: [UserEntryInfo.pasteboardUTType.identifier]
                )
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
        toggleFavorite: @escaping (AnimeEntry) -> Void
    ) -> some View {
        ControlGroup {
            favoriteButton(for: entry, toggleFavorite: toggleFavorite)
            shareButton(for: entry)
        }
        editButton(for: entry)
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
        detailRepository: LibraryRepository,
        resolveEntry: @escaping (LibraryEntrySyncIdentity) -> AnimeEntry?,
        detailPresentation: LibraryPresentationPolicy.DetailPresentation,
        detailSession: EntryDetailSession?
    ) -> some View {
        let activeSheet = Binding<ResolvedLibraryEntrySheet?>(
            get: {
                if let workflow = state.activeWorkflow,
                    let entry = resolveEntry(workflow.entryIdentity)
                {
                    return .workflow(workflow, entry)
                }

                guard detailPresentation == .sheet,
                    let identity = state.presentedDetailEntryID,
                    detailSession?.entryIdentity == identity,
                    let entry = resolveEntry(identity)
                else { return nil }
                return .detail(entry)
            },
            set: { destination in
                switch destination {
                case .detail(let entry):
                    state.presentedDetailEntryID = entry.syncIdentity
                case .workflow(let workflow, _):
                    state.activeWorkflow = workflow
                case nil:
                    if state.activeWorkflow != nil {
                        state.activeWorkflow = nil
                    } else {
                        state.detailHostDidDismiss(.sheet)
                    }
                }
            }
        )

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
                    get: { state.showPasteAlert },
                    set: { state.showPasteAlert = $0 }
                ),
                presenting: state.pasteAction
            ) { action in
                Button("Paste", role: .destructive, action: action)
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This anime already has edits. Pasting will overwrite current info.")
            }
            .sheet(
                item: activeSheet
            ) { destination in
                switch destination {
                case .detail(let entry):
                    NavigationStack {
                        if let detailSession,
                            detailSession.entryIdentity == entry.syncIdentity
                        {
                            EntryDetailView(
                                entry: entry,
                                repository: detailRepository,
                                onClose: state.dismissDetails,
                                session: detailSession
                            )
                        }
                    }
                    .onAppear {
                        state.detailHostDidPresent(.sheet)
                    }
                case .workflow(.editing(_), let entry):
                    NavigationStack {
                        EntryDetailView(
                            entry: entry,
                            repository: detailRepository,
                            startInEditingMode: true
                        )
                    }
                case .workflow(.posterSelection(_), let entry):
                    NavigationStack {
                        PosterSelectionView(
                            tmdbID: entry.tmdbID,
                            type: entry.type,
                            originalPosterLanguageCode: entry.originalLanguageCode
                                ?? entry.parentSeriesEntry?.originalLanguageCode
                        ) { url in
                            if url != entry.posterURL
                                || !entry.usingCustomPoster
                            {
                                entry.updateCustomPosterURL(url)
                            }
                        }
                        .navigationTitle("Pick a poster")
                    }
                case .workflow(.sharing(_), let entry):
                    AnimeSharingSheet(entry: entry)
                }
            }
    }
}

fileprivate enum ResolvedLibraryEntrySheet: Identifiable {
    case detail(AnimeEntry)
    case workflow(LibraryEntryWorkflow, AnimeEntry)

    var id: String {
        switch self {
        case .detail(let entry):
            "detail:\(entry.syncIdentity.rawID)"
        case .workflow(let workflow, _):
            workflow.id
        }
    }
}
