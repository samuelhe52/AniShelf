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
    var detailingEntry: AnimeEntry?
    var deletingEntry: AnimeEntry?
    var isDeletingEntry: Bool = false
    var editingEntry: AnimeEntry?
    var switchingPosterForEntry: AnimeEntry?
    var sharingAnimeEntry: AnimeEntry?
    var showPasteAlert: Bool = false
    var pasteAction: (() -> Void)?

    func setScrolledIDBeforeDeletion(for entry: AnimeEntry, in store: LibraryStore, scrolledID: Binding<Int?>) {
        if let index = store.libraryOnDisplay.firstIndex(of: entry) {
            if index != 0 {
                scrolledID.wrappedValue = store.libraryOnDisplay[index - 1].tmdbID
            } else {
                scrolledID.wrappedValue = store.libraryOnDisplay.last?.tmdbID
            }
        }
    }

    func prepareDeletion(for entry: AnimeEntry, store: LibraryStore, scrolledID: Binding<Int?>) {
        setScrolledIDBeforeDeletion(for: entry, in: store, scrolledID: scrolledID)
        deletingEntry = entry
        isDeletingEntry = true
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
        Binding(
            get: { highlightedEntryID.wrappedValue == entry.tmdbID },
            set: { if !$0 { highlightedEntryID.wrappedValue = nil } }
        )
    }
}

extension LibraryEntryInteractionState {
    @ViewBuilder
    func contextMenu(
        for entry: AnimeEntry,
        store: LibraryStore,
        scrolledID: Binding<Int?>,
        toggleFavorite: @escaping (AnimeEntry) -> Void
    ) -> some View {
        ControlGroup {
            EntryFavoriteButton(favorited: entry.favorite) {
                toggleFavorite(entry)
                if entry.favorite {
                    ToastCenter.global.favorited = true
                } else {
                    ToastCenter.global.unFavorited = true
                }
            }
            Button("Share", systemImage: "square.and.arrow.up") {
                self.sharingAnimeEntry = entry
            }
        }
        Button("Edit", systemImage: "pencil") {
            self.editingEntry = entry
        }
        Button("Switch Poster", systemImage: "photo.badge.magnifyingglass") {
            self.switchingPosterForEntry = entry
        }
        Divider()
        if let posterURL = entry.posterURL {
            ShareLink(item: posterURL) {
                Label("Save Poster", systemImage: "photo.badge.arrow.down")
            }
        }
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
        Button("Delete", systemImage: "trash", role: .destructive) {
            self.prepareDeletion(for: entry, store: store, scrolledID: scrolledID)
        }

    }
}

extension View {
    func libraryEntryInteractionOverlays(
        state: LibraryEntryInteractionState,
        store: LibraryStore
    ) -> some View {
        self
            .alert(
                "Delete Anime?",
                isPresented: Binding(
                    get: { state.isDeletingEntry },
                    set: { state.isDeletingEntry = $0 }
                ),
                presenting: state.deletingEntry
            ) { entry in
                Button("Delete", role: .destructive) { store.deleteEntry(entry) }
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
                    EntryDetailView(entry: entry)
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
                    AnimeEntryEditor(entry: entry)
                }
            }
    }
}
