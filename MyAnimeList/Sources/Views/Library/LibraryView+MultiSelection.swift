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

    var allFavorite: Bool {
        let entries = selectedEntries
        return !entries.isEmpty && entries.allSatisfy(\.favorite)
    }

    func applyBatchAction(_ action: LibraryBatchAction) {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }

        action.apply(to: entries)
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

        let remainingEntries = store.libraryOnDisplay.filter { entry in
            !interaction.selectedEntryIDs.contains(entry.tmdbID)
        }
        let scrollTarget = remainingEntries.first?.tmdbID

        for entry in entries {
            _ = store.deleteEntry(entry)
        }

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
        selectionEntriesByID.removeAll(keepingCapacity: true)
    }

    func refreshSelectionDisplayItemsIfNeeded() {
        guard interaction.isMultiSelecting else { return }
        updateSelectionDisplayItems()
    }

    private func updateSelectionDisplayItems() {
        let items = store.libraryDisplayItems
        let displayedIDs = Set(items.map(\.id))
        interaction.selectedEntryIDs.formIntersection(displayedIDs)
        selectionDisplayItems = items
        selectionEntriesByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.entry) }
        )
    }
}
