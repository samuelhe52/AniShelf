//
//  LibraryEntryInteractionState.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/10/13.
//

import DataProvider
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class LibraryEntryInteractionState {
    enum DeletionScrollTarget: Equatable {
        case preserveCurrent
        case clear
        case entry(Int)
    }

    var detailingEntry: AnimeEntry?
    var deletingEntry: AnimeEntry?
    var isDeletingEntry: Bool = false
    var editingEntry: AnimeEntry?
    var switchingPosterForEntry: AnimeEntry?
    var sharingAnimeEntry: AnimeEntry?
    var showPasteAlert: Bool = false
    var pasteAction: (() -> Void)?

    func deletionScrollTarget(for entry: AnimeEntry, in entries: [AnimeEntry]) -> DeletionScrollTarget {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return .preserveCurrent
        }

        if index > 0 {
            return .entry(entries[index - 1].tmdbID)
        }

        let nextIndex = index + 1
        guard nextIndex < entries.endIndex else {
            return .clear
        }
        return .entry(entries[nextIndex].tmdbID)
    }

    func prepareDeletion(for entry: AnimeEntry) {
        deletingEntry = entry
        isDeletingEntry = true
    }

    func confirmDeletion(
        in entries: [AnimeEntry],
        deleteEntry: (AnimeEntry) -> Bool,
        scrolledID: Binding<Int?>
    ) {
        guard let entry = deletingEntry else { return }

        let scrollTarget = deletionScrollTarget(for: entry, in: entries)
        clearDeletionRequest()

        guard deleteEntry(entry) else { return }

        switch scrollTarget {
        case .preserveCurrent:
            break
        case .clear:
            scrolledID.wrappedValue = nil
        case .entry(let targetID):
            scrolledID.wrappedValue = targetID
        }
    }

    func clearDeletionRequest() {
        deletingEntry = nil
        isDeletingEntry = false
    }

    func setEditingEntry(_ entry: AnimeEntry) {
        editingEntry = entry
    }

    func pasteInfo(for entry: AnimeEntry) {
        if let pasted = UserEntryInfo.fromPasteboard() {
            let paste = {
                entry.updateUserInfo(from: pasted)
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
            self.sharingAnimeEntry = entry
        }
    }

    func editButton(for entry: AnimeEntry) -> some View {
        Button("Edit", systemImage: "pencil") {
            self.editingEntry = entry
        }
    }

    func switchPosterButton(for entry: AnimeEntry) -> some View {
        Button("Switch Poster", systemImage: "photo.badge.magnifyingglass") {
            self.switchingPosterForEntry = entry
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
        displayedEntries: [AnimeEntry],
        deleteEntry: @escaping (AnimeEntry) -> Bool,
        detailRepository: LibraryRepository,
        scrolledID: Binding<Int?>
    ) -> some View {
        self
            .alert(
                "Delete Anime?",
                isPresented: Binding(
                    get: { state.isDeletingEntry },
                    set: {
                        if $0 {
                            state.isDeletingEntry = true
                        } else {
                            state.clearDeletionRequest()
                        }
                    }
                ),
                presenting: state.deletingEntry
            ) { _ in
                Button("Delete", role: .destructive) {
                    state.confirmDeletion(
                        in: displayedEntries,
                        deleteEntry: deleteEntry,
                        scrolledID: scrolledID
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
                item: Binding(
                    get: { state.detailingEntry },
                    set: { state.detailingEntry = $0 }
                )
            ) { entry in
                NavigationStack {
                    EntryDetailView(
                        entry: entry,
                        repository: detailRepository
                    )
                }
            }
            .sheet(
                item: Binding(
                    get: { state.switchingPosterForEntry },
                    set: { state.switchingPosterForEntry = $0 }
                )
            ) { entry in
                NavigationStack {
                    PosterSelectionView(tmdbID: entry.tmdbID, type: entry.type) { url in
                        if url != entry.posterURL {
                            entry.usingCustomPoster = true
                        }
                        entry.posterURL = url
                    }
                    .navigationTitle("Pick a poster")
                }
            }
            .sheet(
                item: Binding(
                    get: { state.sharingAnimeEntry },
                    set: { state.sharingAnimeEntry = $0 }
                )
            ) { entry in
                AnimeSharingSheet(entry: entry)
            }
            .sheet(
                item: Binding(
                    get: { state.editingEntry },
                    set: { state.editingEntry = $0 }
                )
            ) { entry in
                NavigationStack {
                    EntryDetailView(
                        entry: entry,
                        repository: detailRepository,
                        startInEditingMode: true
                    )
                }
            }
    }
}
