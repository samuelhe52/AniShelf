//
//  LibraryView+MultiSelection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import SwiftUI

#if !os(macOS)
    extension LibraryView {
        var supportsMultiSelection: Bool {
            libraryViewStyle == .list || libraryViewStyle == .grid
        }

        var selectedEntries: [AnimeEntry] {
            interaction.selectedEntryIDs.compactMap(scope.displayedEntry(for:))
        }

        func applyBatchAction(_ action: LibraryBatchAction) {
            let entries = selectedEntries
            guard !entries.isEmpty else { return }

            LibraryBenchmarkSignposts.batchActionWillApply()
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

            // The page keeps its position; rows below move up into the deleted ones' places.
            guard store.deleteEntries(entries) else { return }
            exitMultiSelection()
        }

        func enterMultiSelection() {
            withAnimation(LibraryViewTransitions.selectionModeAnimation()) {
                interaction.enterMultiSelection()
            }
        }

        func exitMultiSelection() {
            withAnimation(LibraryViewTransitions.selectionModeAnimation()) {
                interaction.exitMultiSelection()
            }
        }

        /// Keeps the selection to the entries still shown after a library or scope change.
        func pruneSelection() {
            guard interaction.isMultiSelecting else { return }
            interaction.selectedEntryIDs.formIntersection(scope.displayIDs)
        }
    }
#endif
