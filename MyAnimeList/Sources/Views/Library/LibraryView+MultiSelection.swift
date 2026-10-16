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
        guard action.endsMultiSelection else { return }
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

    /// Keeps the selection to the entries still shown after a library, scope, or Find change.
    func refreshSelectionDisplayItemsIfNeeded() {
        #if os(macOS)
            macSelection.prune(keeping: Set(visibleDisplayItems.map(\.id)))
        #else
            guard interaction.isMultiSelecting else { return }
            updateSelectionDisplayItems()
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
