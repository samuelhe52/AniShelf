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

    /// Whether the trailing inspector is showing, with entry detail or the Mac batch panel.
    var isInspectorShown: Bool {
        #if os(macOS)
            interaction.inspectorPresentation != nil || isMacBatchInspectorShown
        #else
            interaction.inspectorPresentation != nil
        #endif
    }

    func hideBatchInspector() {
        #if os(macOS)
            isBatchInspectorHidden = true
        #endif
    }

    /// Shows the inspector for the targeted entry, or hides it.
    func toggleInspector() {
        #if os(macOS)
            // During a batch selection the inspector holds the batch panel.
            if interaction.isMultiSelecting {
                isBatchInspectorHidden.toggle()
                return
            }
        #endif
        if interaction.inspectorPresentation != nil {
            interaction.dismissDetails()
        } else if let entry = inspectorReopenTarget {
            openDetails(entry)
        }
    }

    /// The entry that menu commands act on.
    var commandTargetEntry: AnimeEntry? {
        guard !interaction.isMultiSelecting else { return nil }
        #if os(macOS)
            // Desktop commands act only on the visible selection, which is the inspected entry;
            // the last focused entry may since have been deselected or left the scope.
            let identity = interaction.presentedDetailEntryID
        #else
            let identity = interaction.presentedDetailEntryID ?? interaction.focusedEntryID
        #endif
        guard let identity else { return nil }
        return store.repository.existingEntry(identity: identity)
    }

    /// The entry that showing the inspector inspects.
    private var inspectorReopenTarget: AnimeEntry? {
        #if os(macOS)
            // Reopen the last inspected entry while it is still shown.
            let displayed = visibleDisplayItems.map(\.entry)
            return interaction.focusedEntryID.flatMap { id in
                displayed.first { $0.libraryIdentity == id }
            } ?? displayed.first
        #else
            commandTargetEntry ?? store.libraryOnDisplay.first
        #endif
    }
}
