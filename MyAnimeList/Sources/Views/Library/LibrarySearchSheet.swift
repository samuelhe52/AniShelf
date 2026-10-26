//
//  LibrarySearchSheet.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import Collections
import DataProvider
import SwiftUI

extension View {
    /// Hosts the search page.
    ///
    /// Attach it to a view that outlives toolbar changes: menu commands
    /// open search during batch selection, when the toolbar shows no search button.
    func librarySearchSheet(
        isPresented: Binding<Bool>,
        checkDuplicate: @escaping (LibraryEntryIdentity) -> Bool,
        canRevealEntry: @escaping (LibraryEntryIdentity) -> Bool,
        resetFiltersToReveal: @escaping (LibraryEntryIdentity) -> Void,
        processTMDbSearchResults: @escaping (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void,
        jumpToEntryInLibrary: @escaping (LibraryEntryIdentity) -> Void,
        onDismiss: @escaping () -> Void,
        initialMode: SearchMode? = nil
    ) -> some View {
        modifier(
            LibrarySearchSheet(
                isSearching: isPresented,
                checkDuplicate: checkDuplicate,
                canRevealEntry: canRevealEntry,
                resetFiltersToReveal: resetFiltersToReveal,
                processTMDbSearchResults: processTMDbSearchResults,
                jumpToEntryInLibrary: jumpToEntryInLibrary,
                onDismiss: onDismiss,
                initialMode: initialMode
            )
        )
    }
}

fileprivate struct LibrarySearchSheet: ViewModifier {
    @Binding var isSearching: Bool
    let checkDuplicate: (LibraryEntryIdentity) -> Bool
    let canRevealEntry: (LibraryEntryIdentity) -> Bool
    let resetFiltersToReveal: (LibraryEntryIdentity) -> Void
    let processTMDbSearchResults: (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void
    let jumpToEntryInLibrary: (LibraryEntryIdentity) -> Void
    let onDismiss: () -> Void
    /// Opens the page in this mode instead of the last-used one.
    let initialMode: SearchMode?

    @State private var hiddenEntryID: LibraryEntryIdentity?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isSearching, onDismiss: sheetDidDismiss) {
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
                    .preferredNavigationBarScrollEdgeEffect()
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

    private func sheetDidDismiss() {
        // The modifier outlives the sheet, so a stale alert must not reappear on the next opening.
        hiddenEntryID = nil
        onDismiss()
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
