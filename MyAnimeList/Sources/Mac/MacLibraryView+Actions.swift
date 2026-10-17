//
//  MacLibraryView+Actions.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/15.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    extension MacLibraryView {
        /// The inspector's content, which follows this window's selection.
        var inspector: some View {
            MacLibraryInspector(
                store: store,
                selection: selection,
                displayItems: visibleDisplayItems,
                detailSessionStore: detailSessionStore,
                editRequest: $editRequest,
                scoringEnabled: scoringEnabled,
                applyBatchAction: applyBatchAction,
                deleteEntries: deleteEntries,
                isPresented: $isInspectorShown
            )
        }

        var windowTitle: Text {
            switch scope.macLibraryScope {
            case .all:
                Text("All Anime")
            case .filter(let id):
                if let filter = LibraryStore.AnimeFilter(preferenceID: id) {
                    filter.id == LibraryStore.AnimeFilter.planToWatch.id
                        ? Text("Plan to Watch") : Text(filter.name)
                } else {
                    Text("Library")
                }
            case .category:
                Text(verbatim: scope.activeCategory?.name ?? "")
            case nil:
                scope.filters.count > 1 ? Text("\(scope.filters.count) Filters") : Text("Library")
            }
        }

        /// Reads the selection, so only call it from a view that depends on the selection.
        var commandActions: MacLibraryCommandActions {
            let selectionCount = selection.ids.count
            return MacLibraryCommandActions(
                addAnime: { openSearch(mode: .tmdb) },
                findInLibrary: { isLibraryFindFocused = true },
                viewStyle: Binding(
                    get: { libraryViewStyle },
                    set: { style in
                        withAnimation(LibraryViewTransitions.libraryViewStyleAnimation()) {
                            libraryViewStyle = style
                        }
                    }
                ),
                isInspectorPresented: isInspectorShown,
                toggleInspector: toggleInspector,
                hasSelection: selectionCount > 0,
                hasBatchSelection: selectionCount > 1,
                selectAll: selectAllDisplayedEntries,
                clearSelection: { selection.select([]) },
                openCategoryManager: openCategoryManager,
                refreshAllMetadata: { showRefreshAllMetadataAlert = true },
                isRefreshingAllMetadata: store.isRefreshingAllMetadata,
                targetEntry: selection.single.flatMap { store.repository.existingEntry(identity: $0) },
                openDetails: openDetails,
                editEntry: editDetails,
                toggleFavorite: { entry in
                    store.repository.toggleFavorite(entry)
                    if entry.favorite {
                        ToastCenter.global.favorited = true
                    } else {
                        ToastCenter.global.unFavorited = true
                    }
                },
                shareEntry: { actions.presentWorkflow(.sharing($0.libraryIdentity)) },
                switchPoster: { actions.presentWorkflow(.posterSelection($0.libraryIdentity)) },
                deleteEntry: { actions.prepareDeletion(for: $0) },
                deleteSelection: { pendingBatchDeletion = selectedEntries }
            )
        }

        /// The selected entries in layout order.
        private var selectedEntries: [AnimeEntry] {
            let ids = selection.ids
            return visibleDisplayItems.filter { ids.contains($0.id) }.map(\.entry)
        }

        /// Selects an entry and shows it in the inspector, as double-click, Show Details, and
        /// an airing reminder do.
        ///
        /// Scope and Find give way when they hide the entry.
        func revealInInspector(_ id: LibraryEntryIdentity) {
            if !visibleDisplayItems.contains(where: { $0.id == id }) {
                find.clear()
                scope.leaveCategoryToReveal(id)
                if !scope.canRevealEntry(id) { scope.resetFiltersToReveal(id) }
            }
            showInInspector(id)
            browse.requestScroll(to: id)
        }

        /// Makes an entry the selection and shows the inspector.
        func showInInspector(_ id: LibraryEntryIdentity) {
            selection.select([id])
            if !isInspectorShown {
                withAnimation { isInspectorShown = true }
            }
        }

        func selectAllDisplayedEntries() {
            selection.select(Set(visibleDisplayItems.map(\.id)))
        }

        func applyBatchAction(_ entries: [AnimeEntry], _ action: LibraryBatchAction) {
            guard !entries.isEmpty else { return }
            // A desktop selection stays until the user changes it, as in Finder, so several
            // actions can apply to it. Entries the action moves out of scope leave it.
            action.apply(to: entries)
            pruneSelection()
            if entries.count >= 3 { appReview.record(.multiSelectAction) }
        }

        func deleteEntries(_ entries: [AnimeEntry]) {
            guard !entries.isEmpty else { return }
            let deleted = Set(entries.map(\.libraryIdentity))
            let scrollTarget = visibleDisplayItems.first { !deleted.contains($0.id) }?.id
            guard store.deleteEntries(entries) else { return }
            browse.requestScroll(to: scrollTarget)
            pruneSelection()
        }

        /// Saves the selection for this window's restoration, and remembers a single selection
        /// as the last-inspected entry, which a window without saved state opens on.
        func persistSelection(_ ids: Set<LibraryEntryIdentity>) {
            if ids != lastAppliedSelection { selectionAcceptsRestoration = false }
            storedSelection = Self.storedSelectionValue(ids)
            if ids.isEmpty {
                persistedLastInspectorDetailEntryIdentity = nil
            } else if ids.count == 1, let id = ids.first {
                persistedLastInspectorDetailEntryIdentity = id.rawID
            }
        }

        /// Restores this window's Find text and selection, falling back to the last-inspected
        /// entry for a window that has never saved a selection.
        func restoreWindowState() {
            if find.text.isEmpty, !storedFindText.isEmpty {
                find.text = storedFindText
            }
            lastAppliedFindText = find.text
            if selection.isEmpty {
                if let storedSelection {
                    pendingRestoredSelection = Self.rawIDs(in: storedSelection)
                    selectVisible(pendingRestoredSelection ?? [])
                } else if let rawID = persistedLastInspectorDetailEntryIdentity {
                    selectVisible([rawID])
                }
            }
            lastAppliedSelection = selection.ids
        }

        /// Applies Find text restored after the window appeared; once the user has typed, the
        /// live text replaces it instead.
        func restoreFindText(_ text: String) {
            guard find.text != text else { return }
            if findAcceptsRestoration {
                lastAppliedFindText = text
                find.text = text
            } else {
                storedFindText = find.text
            }
        }

        /// Applies a selection restored after the window appeared; once the user has changed the
        /// selection, the live selection replaces it instead.
        func restoreSelection(fromStored stored: String) {
            let rawIDs = Self.rawIDs(in: stored)
            // An echo of this window's own save, which may hold only the part of a restored
            // selection shown so far, must not replace the pending restoration.
            guard rawIDs != Set(selection.ids.map(\.rawID)) else { return }
            if acceptsSelectionRestoration {
                pendingRestoredSelection = rawIDs
                applyPendingRestoredSelection()
            } else {
                storedSelection = Self.storedSelectionValue(selection.ids)
            }
        }

        /// Whether a restored selection may still apply: the user has changed none of the
        /// selection, the scope, or Find, all of which decide what the selection can show.
        ///
        /// The live comparison also catches a click whose persistence has not run yet.
        private var acceptsSelectionRestoration: Bool {
            selectionAcceptsRestoration && selection.ids == lastAppliedSelection
                && findAcceptsRestoration && scope.acceptsSceneRestoration
        }

        /// Reselects the restored entries this window now shows, as its restored scope and Find
        /// settle.
        ///
        /// Returns `false`, leaving ordinary pruning, once restoration has closed or when nothing
        /// is pending.
        @discardableResult
        func applyPendingRestoredSelection() -> Bool {
            guard acceptsSelectionRestoration, let pendingRestoredSelection else { return false }
            selectVisible(pendingRestoredSelection)
            lastAppliedSelection = selection.ids
            return true
        }

        /// Selects the entries with these raw IDs that this window shows.
        private func selectVisible(_ rawIDs: Set<String>) {
            let ids = Set(visibleDisplayItems.lazy.map(\.id).filter { rawIDs.contains($0.rawID) })
            if ids != selection.ids { selection.select(ids) }
        }

        private static func rawIDs(in stored: String) -> Set<String> {
            Set(stored.split(separator: "\n").map(String.init))
        }

        private static func storedSelectionValue(_ ids: Set<LibraryEntryIdentity>) -> String {
            ids.map(\.rawID).sorted().joined(separator: "\n")
        }
    }

    /// The window state that depends on the selection.
    ///
    /// Kept out of `MacLibraryView`'s body so a click does not recompute the library's display items.
    struct MacLibrarySelectionObservers: ViewModifier {
        let selection: MacLibrarySelection
        let makeCommandActions: () -> MacLibraryCommandActions
        let persistSelection: (Set<LibraryEntryIdentity>) -> Void

        func body(content: Content) -> some View {
            content
                .focusedSceneValue(\.macLibraryCommands, makeCommandActions())
                .onChange(of: selection.ids) { _, ids in persistSelection(ids) }
        }
    }

    /// The window subtitle: the selection count during a batch selection, else the entry count.
    struct MacLibrarySubtitle: ViewModifier {
        let selection: MacLibrarySelection
        let visibleCount: Int

        func body(content: Content) -> some View {
            let selectedCount = selection.ids.count
            content.navigationSubtitle(
                selectedCount > 1 ? Text("\(selectedCount) Selected") : Text("\(visibleCount) Anime")
            )
        }
    }
#endif
