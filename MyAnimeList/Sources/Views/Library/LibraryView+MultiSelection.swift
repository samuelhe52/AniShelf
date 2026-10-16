//
//  LibraryView+MultiSelection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import SwiftUI

extension LibraryView {
    var supportsMultiSelection: Bool {
        libraryViewStyle == .list || libraryViewStyle == .grid
    }

    var selectedEntries: [AnimeEntry] {
        interaction.selectedEntryIDs.compactMap { selectionEntriesByID[$0] }
    }

    func applyBatchAction(_ action: LibraryBatchAction) {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }

        action.apply(to: entries)
        #if os(macOS)
            // A desktop selection stays until the user changes it, as in Finder, so several
            // actions can apply to it. Entries the action moves out of scope leave it through
            // the snapshot refresh.
            let endsSelection = false
        #else
            let endsSelection = action.endsMultiSelection
        #endif
        guard endsSelection else {
            #if os(macOS)
                // The snapshot holds the old badges, and entries the action moved out of the
                // filter must leave the selection before another action reaches them.
                refreshSelectionDisplayItemsIfNeeded()
                if entries.count >= 3 { appReview.record(.multiSelectAction) }
            #endif
            return
        }
        exitMultiSelection()
        if entries.count >= 3 {
            appReview.record(.multiSelectAction)
        }
    }

    func deleteSelectedEntries() {
        let entries = selectedEntries
        guard !entries.isEmpty else {
            exitMultiSelection()
            return
        }

        let remainingEntries = visibleDisplayItems.map(\.entry).filter { entry in
            !interaction.selectedEntryIDs.contains(entry.libraryIdentity)
        }
        let scrollTarget = remainingEntries.first?.libraryIdentity

        guard store.deleteEntries(entries) else { return }

        requestLibraryScroll(to: scrollTarget)
        exitMultiSelection()
    }

    func enterMultiSelection() {
        updateSelectionDisplayItems()
        withAnimation(LibraryViewTransitions.selectionModeAnimation()) {
            interaction.enterMultiSelection()
        }
    }

    func exitMultiSelection() {
        withAnimation(LibraryViewTransitions.selectionModeAnimation()) {
            interaction.exitMultiSelection()
        }
        selectionDisplayItems = nil
        selectionLayoutIDs = nil
        selectionEntriesByID.removeAll(keepingCapacity: true)
    }

    func refreshSelectionDisplayItemsIfNeeded() {
        guard interaction.isMultiSelecting else { return }
        updateSelectionDisplayItems()
        #if os(macOS)
            // A scope or Find change can leave one or no selected entries; the Mac then shows
            // that entry, or nothing, instead of a batch of one or zero. iOS keeps its
            // explicit selection mode.
            if interaction.selectedEntryIDs.count <= 1 {
                applyMacSelection(interaction.selectedEntryIDs)
            }
        #endif
    }

    private func updateSelectionDisplayItems() {
        let items = visibleDisplayItems
        let layoutIDs = items.map(\.id)
        let displayedIDs = Set(layoutIDs)
        interaction.selectedEntryIDs.formIntersection(displayedIDs)
        selectionDisplayItems = items
        selectionLayoutIDs = layoutIDs
        selectionEntriesByID = Dictionary(
            items.map { ($0.id, $0.entry) },
            uniquingKeysWith: { existing, candidate in
                AnimeEntryDuplicateResolver.prefers(candidate, existing) ? candidate : existing
            }
        )
    }
}
