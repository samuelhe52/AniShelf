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

    func openSearch(mode: SearchMode) {
        #if os(macOS)
            searchInitialMode = mode
        #endif
        isSearching = true
    }

    /// Shows the inspector for the targeted entry, or hides it.
    func toggleInspector() {
        #if os(macOS)
            // Inspecting during a batch selection narrows it to one entry first.
            if interaction.isMultiSelecting {
                let id =
                    macSelectionAnchor.flatMap { interaction.selectedEntryIDs.contains($0) ? $0 : nil }
                    ?? interaction.selectedEntryIDs.first
                if let id { applyMacSelection([id]) }
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
            let displayed = store.libraryOnDisplay
            return interaction.focusedEntryID.flatMap { id in
                displayed.first { $0.libraryIdentity == id }
            } ?? displayed.first
        #else
            commandTargetEntry ?? store.libraryOnDisplay.first
        #endif
    }
}
