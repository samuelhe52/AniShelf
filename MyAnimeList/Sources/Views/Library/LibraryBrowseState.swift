//
//  LibraryBrowseState.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import Collections
import DataProvider
import Observation
import SwiftUI

struct LibraryScrollRequest: Equatable {
    // Keep repeated explicit requests to the same entry observable.
    let token = UUID()
    let entryID: LibraryEntryIdentity?
}

struct LibraryHighlightRequest: Equatable {
    // A fresh token restarts the pulse even when the same entry is requested again.
    let token = UUID()
    let entryID: LibraryEntryIdentity

    /// Long enough for a row created late in the jump scroll to finish its pulse.
    static let lifetime: Duration = .seconds(2.5)

    func trigger(for entryID: LibraryEntryIdentity) -> UUID? {
        self.entryID == entryID ? token : nil
    }
}

/// A library window's scroll position, jump highlight, and search sheet, shared by the iOS
/// and Mac library roots.
@Observable
@MainActor
final class LibraryBrowseState {
    let scrollState = ScrollState()
    private(set) var scrollRequest: LibraryScrollRequest?
    var highlightRequest: LibraryHighlightRequest?
    var isSearching = false
    private(set) var newEntriesAddedToggle = false
    // A jump from search waits for the sheet to finish dismissing so it is not hidden behind it.
    private var isSearchSheetOnScreen = false
    private var pendingJumpEntryID: LibraryEntryIdentity?

    func requestScroll(to entryID: LibraryEntryIdentity?) {
        scrollState.scrolledID = entryID
        scrollRequest = LibraryScrollRequest(entryID: entryID)
    }

    func searchDidPresent() {
        isSearchSheetOnScreen = true
    }

    /// Scrolls to and highlights an entry, after the search sheet dismisses if it is showing.
    /// `reveal` makes the entry visible and selected the way the platform needs.
    func jump(
        to id: LibraryEntryIdentity,
        store: LibraryStore,
        reveal: (LibraryEntryIdentity) -> Void
    ) {
        // Defer a jump from search until the sheet has dismissed so the scroll and pulse play in view.
        if isSearchSheetOnScreen {
            pendingJumpEntryID = id
        } else {
            performJump(to: id, store: store, reveal: reveal)
        }
    }

    func searchSheetDidDismiss(store: LibraryStore, reveal: (LibraryEntryIdentity) -> Void) {
        isSearchSheetOnScreen = false
        guard let pendingJumpEntryID else { return }
        self.pendingJumpEntryID = nil
        performJump(to: pendingJumpEntryID, store: store, reveal: reveal)
    }

    private func performJump(
        to id: LibraryEntryIdentity,
        store: LibraryStore,
        reveal: (LibraryEntryIdentity) -> Void
    ) {
        reveal(id)
        // Search spans the whole library, so leave a category that hides the entry.
        if store.activeCategoryID != nil,
            !store.libraryOnDisplay.contains(where: { $0.libraryIdentity == id })
        {
            withAnimation(.snappy) { store.activeCategoryID = nil }
        }
        requestScroll(to: id)
        highlightRequest = LibraryHighlightRequest(entryID: id)
    }

    func processTMDbSearchResults(
        _ results: OrderedSet<SearchResult>,
        origin: SearchSubmissionOrigin,
        store: LibraryStore,
        appReview: AppReviewPromptController,
        reveal: @escaping (LibraryEntryIdentity) -> Void
    ) {
        isSearching = false
        Task {
            ToastCenter.global.loadingMessage = .message("Loading...")
            let success = await store.newEntryFromSearchResults(results)
            if success {
                appReview.record(origin == .regular ? .regularSearchAdd : .batchSearchAdd)
                ToastCenter.global.loadingMessage = nil
                withAnimation {
                    newEntriesAddedToggle.toggle()
                    if let id = results.first?.libraryIdentity {
                        jump(to: id, store: store, reveal: reveal)
                    }
                }
            }
        }
    }
}

extension View {
    /// The search sheet, the add-success haptic, and the jump to an entry search found or added.
    func libraryBrowseSearch(
        _ browse: LibraryBrowseState,
        store: LibraryStore,
        appReview: AppReviewPromptController,
        initialMode: SearchMode? = nil,
        reveal: @escaping (LibraryEntryIdentity) -> Void
    ) -> some View {
        @Bindable var browse = browse
        return
            self
            .sensoryFeedback(.success, trigger: browse.newEntriesAddedToggle)
            .onChange(of: browse.isSearching) {
                if browse.isSearching { browse.searchDidPresent() }
            }
            .librarySearchSheet(
                isPresented: $browse.isSearching,
                checkDuplicate: store.containsEntry,
                canRevealEntry: store.canRevealEntry,
                resetFiltersToReveal: store.resetFiltersToReveal,
                processTMDbSearchResults: { results, origin in
                    browse.processTMDbSearchResults(
                        results, origin: origin, store: store, appReview: appReview, reveal: reveal)
                },
                jumpToEntryInLibrary: { browse.jump(to: $0, store: store, reveal: reveal) },
                onDismiss: { browse.searchSheetDidDismiss(store: store, reveal: reveal) },
                initialMode: initialMode
            )
    }
}
