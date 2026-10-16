//
//  MacLibrarySelection.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

#if os(macOS)
    import DataProvider
    import Observation

    /// The selection of one library window, as in Finder or Mail: a set of entries that clicks,
    /// arrow keys, and the list change. The inspector shows whatever is selected; selecting
    /// never opens or closes it.
    ///
    /// Views that depend on the selection read it themselves, so a click does not re-run the
    /// library view's body and recompute its display items.
    @Observable
    @MainActor
    final class MacLibrarySelection {
        private(set) var ids: Set<LibraryEntryIdentity> = []
        /// Where a ⇧-click range starts: the entry of the last plain or ⌘-click. It is also
        /// the entry the batch panel puts on top of its stack.
        private(set) var anchor: LibraryEntryIdentity?

        /// The selected entry when exactly one is selected.
        var single: LibraryEntryIdentity? {
            ids.count == 1 ? ids.first : nil
        }

        var isEmpty: Bool { ids.isEmpty }

        /// Applies a click from a view that does not select natively, such as the grid.
        func click(
            _ id: LibraryEntryIdentity,
            _ click: MacSelectionClick,
            layoutIDs: [LibraryEntryIdentity]
        ) {
            switch click {
            case .replace:
                anchor = id
                ids = [id]
            case .toggle:
                anchor = id
                ids.formSymmetricDifference([id])
            case .extend:
                guard let anchor = anchor ?? ids.first,
                    let anchorIndex = layoutIDs.firstIndex(of: anchor),
                    let index = layoutIDs.firstIndex(of: id)
                else {
                    self.anchor = id
                    ids = [id]
                    return
                }
                ids = Set(layoutIDs[min(anchorIndex, index)...max(anchorIndex, index)])
            }
        }

        /// Replaces the selection, as a list's native selection or Select All does.
        func select(_ newIDs: Set<LibraryEntryIdentity>) {
            // A single selection, however it was made, is where a ⇧-click range starts.
            if newIDs.count <= 1 { anchor = newIDs.first }
            ids = newIDs
        }

        /// Moves a single selection by `offset` places in layout order, as the grid's arrow
        /// keys do, and returns the newly selected entry. With nothing selected the first
        /// entry is selected; at an edge the selection stays put.
        @discardableResult
        func move(by offset: Int, in layoutIDs: [LibraryEntryIdentity]) -> LibraryEntryIdentity? {
            guard !layoutIDs.isEmpty else { return nil }
            let current = anchor.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
            let target: Int
            if let current, let index = layoutIDs.firstIndex(of: current) {
                target = index + offset
            } else {
                target = 0
            }
            guard layoutIDs.indices.contains(target) else { return nil }
            let id = layoutIDs[target]
            select([id])
            return id
        }

        /// Drops entries that are no longer shown, after a scope, Find, or library change.
        func prune(keeping visibleIDs: Set<LibraryEntryIdentity>) {
            guard !ids.isSubset(of: visibleIDs) else { return }
            ids.formIntersection(visibleIDs)
            if let anchor, !ids.contains(anchor) { self.anchor = ids.count == 1 ? ids.first : nil }
        }
    }
#endif
