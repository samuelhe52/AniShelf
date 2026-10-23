//
//  LibraryBrowseState.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
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
        scope: LibraryBrowseScope,
        reveal: (LibraryEntryIdentity) -> Void
    ) {
        // Defer a jump from search until the sheet has dismissed so the scroll and pulse play in view.
        if isSearchSheetOnScreen {
            pendingJumpEntryID = id
        } else {
            performJump(to: id, scope: scope, reveal: reveal)
        }
    }

    func searchSheetDidDismiss(scope: LibraryBrowseScope, reveal: (LibraryEntryIdentity) -> Void) {
        isSearchSheetOnScreen = false
        guard let pendingJumpEntryID else { return }
        self.pendingJumpEntryID = nil
        performJump(to: pendingJumpEntryID, scope: scope, reveal: reveal)
    }

    private func performJump(
        to id: LibraryEntryIdentity,
        scope: LibraryBrowseScope,
        reveal: (LibraryEntryIdentity) -> Void
    ) {
        reveal(id)
        // Search spans the whole library, so leave a category that hides the entry.
        withAnimation(.snappy) { scope.leaveCategoryToReveal(id) }
        requestScroll(to: id)
        highlightRequest = LibraryHighlightRequest(entryID: id)
    }

    func processTMDbSearchResults(
        _ results: OrderedSet<SearchResult>,
        origin: SearchSubmissionOrigin,
        scope: LibraryBrowseScope,
        appReview: AppReviewPromptController,
        reveal: @escaping (LibraryEntryIdentity) -> Void
    ) {
        isSearching = false
        Task {
            ToastCenter.global.loadingMessage = .message("Loading...")
            let success = await scope.store.newEntryFromSearchResults(results)
            // A failure shows its own toast; the loading toast never dismisses itself.
            ToastCenter.global.loadingMessage = nil
            if success {
                appReview.record(origin == .regular ? .regularSearchAdd : .batchSearchAdd)
                withAnimation {
                    newEntriesAddedToggle.toggle()
                    if let id = results.first?.libraryIdentity {
                        jump(to: id, scope: scope, reveal: reveal)
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
        scope: LibraryBrowseScope,
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
                checkDuplicate: scope.store.containsEntry,
                canRevealEntry: scope.canRevealEntry,
                resetFiltersToReveal: scope.resetFiltersToReveal,
                processTMDbSearchResults: { results, origin in
                    browse.processTMDbSearchResults(
                        results, origin: origin, scope: scope, appReview: appReview, reveal: reveal)
                },
                jumpToEntryInLibrary: { browse.jump(to: $0, scope: scope, reveal: reveal) },
                onDismiss: { browse.searchSheetDidDismiss(scope: scope, reveal: reveal) },
                initialMode: initialMode
            )
    }
}
