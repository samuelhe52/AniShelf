//
//  LibraryView+Search.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import Collections
import DataProvider
import SwiftUI

struct LibrarySearchButton: View {
    @Binding var isSearching: Bool
    let checkDuplicate: (LibraryEntryIdentity) -> Bool
    let canRevealEntry: (LibraryEntryIdentity) -> Bool
    let resetFiltersToReveal: (LibraryEntryIdentity) -> Void
    let processTMDbSearchResults: (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void
    let jumpToEntryInLibrary: (LibraryEntryIdentity) -> Void
    let onDismiss: () -> Void
    /// Opens the page in this mode instead of the last-used one.
    var initialMode: SearchMode? = nil

    @State private var hiddenEntryID: LibraryEntryIdentity?

    var body: some View {
        Button("Search...", systemImage: "magnifyingglass") { isSearching = true }
            .sheet(isPresented: $isSearching, onDismiss: onDismiss) {
                NavigationStack {
                    SearchPage(
                        onDuplicateTapped: jumpIfRevealable,
                        checkDuplicate: checkDuplicate,
                        processTMDbSearchResults: processTMDbSearchResults,
                        jumpToEntryInLibrary: jumpIfRevealable,
                        initialMode: initialMode
                    )
                    .navigationTitle("Search")
                    .inlineNavigationTitle()
                    .alert(
                        "Entry Hidden",
                        isPresented: Binding(
                            get: { hiddenEntryID != nil },
                            set: { if !$0 { hiddenEntryID = nil } }
                        ),
                        presenting: hiddenEntryID
                    ) { id in
                        Button("Cancel", role: .cancel) {}
                        Button("Reset Filters") {
                            resetFiltersToReveal(id)
                            jumpIfRevealable(id)
                        }
                    } message: { _ in
                        Text("Your current filters hide this entry. Reset them to see it in your library.")
                    }
                }
            }
    }

    // Keep search open when the jump could not show the entry, instead of dismissing to nothing.
    private func jumpIfRevealable(_ id: LibraryEntryIdentity) {
        guard canRevealEntry(id) else {
            hiddenEntryID = id
            return
        }
        isSearching = false
        jumpToEntryInLibrary(id)
    }
}

extension LibraryView {
    func jumpToEntryInLibrary(withID id: LibraryEntryIdentity) {
        // Defer a jump from search until the sheet has dismissed so the scroll and pulse play in view.
        if isSearchSheetOnScreen {
            pendingJumpEntryID = id
        } else {
            performJump(to: id)
        }
    }

    func searchSheetDidDismiss() {
        isSearchSheetOnScreen = false
        guard let pendingJumpEntryID else { return }
        self.pendingJumpEntryID = nil
        performJump(to: pendingJumpEntryID)
    }

    private func performJump(to id: LibraryEntryIdentity) {
        // Search spans the whole library, so leave a category that hides the entry.
        if store.activeCategoryID != nil,
            !store.libraryOnDisplay.contains(where: { $0.libraryIdentity == id })
        {
            withAnimation(.snappy) { store.activeCategoryID = nil }
        }
        requestLibraryScroll(to: id)
        highlightRequest = LibraryHighlightRequest(entryID: id)
    }

    func processTMDbSearchResults(
        _ results: OrderedSet<SearchResult>,
        origin: SearchSubmissionOrigin
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
                        jumpToEntryInLibrary(withID: id)
                    }
                }
            }
        }
    }
}
