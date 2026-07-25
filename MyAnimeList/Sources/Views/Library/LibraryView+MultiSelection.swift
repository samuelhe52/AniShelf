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
        let entriesByID = Dictionary(
            uniqueKeysWithValues: store.libraryDisplayItems.map { ($0.id, $0.entry) }
        )
        return interaction.selectedEntryIDs.compactMap { entriesByID[$0] }
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

        scrollState.scrolledID = scrollTarget
        exitMultiSelection()
    }

    func enterMultiSelection() {
        interaction.selectedEntryIDs.formIntersection(Set(store.libraryDisplayItems.map(\.id)))
        withAnimation(LibraryViewTransitions.selectionModeAnimation(reduceMotion: reduceMotion)) {
            interaction.enterMultiSelection()
        }
    }

    func exitMultiSelection() {
        withAnimation(LibraryViewTransitions.selectionModeAnimation(reduceMotion: reduceMotion)) {
            interaction.exitMultiSelection()
        }
    }

    func pruneSelection(to displayedIDs: [Int]) {
        guard interaction.isMultiSelecting else { return }
        interaction.selectedEntryIDs.formIntersection(Set(displayedIDs))
    }
}
