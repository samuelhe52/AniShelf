//
//  LibraryView+Commands.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

import DataProvider
import SwiftUI

extension LibraryView {
    /// The search page mode a desktop command asked for; iOS reopens the last-used mode.
    var macSearchInitialMode: SearchMode? {
        #if os(macOS)
            searchInitialMode
        #else
            nil
        #endif
    }

    /// The entries this window shows: the shared scope, narrowed on the Mac by the toolbar Find.
    var visibleDisplayItems: [LibraryEntryDisplayItem] {
        #if os(macOS)
            let query = libraryFindQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return store.libraryDisplayItems }
            let matches = LibrarySearchService.matcher(for: query)
            return store.libraryDisplayItems.filter { matches($0.entry) }
        #else
            store.libraryDisplayItems
        #endif
    }

    func openSearch(mode: SearchMode) {
        #if os(macOS)
            searchInitialMode = mode
        #endif
        isSearching = true
    }

    /// Whether the trailing inspector is showing.
    var isInspectorShown: Bool {
        #if os(macOS)
            isMacInspectorShown
        #else
            interaction.inspectorPresentation != nil
        #endif
    }

    /// Shows or hides the inspector. On the Mac it is the window's setting; on iPad it shows
    /// the focused entry, or hides the shown one.
    func toggleInspector() {
        #if os(macOS)
            withAnimation { isMacInspectorShown.toggle() }
        #else
            if interaction.inspectorPresentation != nil {
                interaction.dismissDetails()
            } else if let entry = inspectorReopenTarget {
                openDetails(entry)
            }
        #endif
    }

    #if !os(macOS)
        /// The entry that showing the inspector inspects.
        private var inspectorReopenTarget: AnimeEntry? {
            let identity =
                interaction.isMultiSelecting
                ? nil : interaction.presentedDetailEntryID ?? interaction.focusedEntryID
            return identity.flatMap { store.repository.existingEntry(identity: $0) }
                ?? store.libraryOnDisplay.first
        }
    #endif
}
