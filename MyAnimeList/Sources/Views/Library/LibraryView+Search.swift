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
    let processTMDbSearchResults: (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void
    let jumpToEntryInLibrary: (LibraryEntryIdentity) -> Void

    var body: some View {
        Button("Search...", systemImage: "magnifyingglass") { isSearching = true }
            .sheet(isPresented: $isSearching) {
                NavigationStack {
                    SearchPage(
                        onDuplicateTapped: { tappedID in
                            isSearching = false
                            jumpToEntryInLibrary(tappedID)
                        },
                        checkDuplicate: checkDuplicate,
                        processTMDbSearchResults: processTMDbSearchResults,
                        jumpToEntryInLibrary: { tmdbID in
                            isSearching = false
                            jumpToEntryInLibrary(tmdbID)
                        }
                    )
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
    }
}

extension LibraryView {
    func jumpToEntryInLibrary(withID id: LibraryEntryIdentity) {
        requestLibraryScroll(to: id)
        highlightedEntryID = id
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
