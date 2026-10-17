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
            switch store.macLibraryScope {
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
                Text(verbatim: store.activeCategory?.name ?? "")
            case nil:
                store.filters.count > 1 ? Text("\(store.filters.count) Filters") : Text("Library")
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
                if store.activeCategoryID != nil,
                    !store.libraryOnDisplay.contains(where: { $0.libraryIdentity == id })
                {
                    store.activeCategoryID = nil
                }
                if !store.canRevealEntry(id) { store.resetFiltersToReveal(id) }
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

        /// Remembers a single selection as the last-inspected entry, as iPad does for its
        /// inspector, so the next window opens on it.
        func persistSelection(_ ids: Set<LibraryEntryIdentity>) {
            if ids.isEmpty {
                persistedLastInspectorDetailEntryIdentity = nil
            } else if ids.count == 1, let id = ids.first {
                persistedLastInspectorDetailEntryIdentity = id.rawID
            }
        }

        func restoreSelection() {
            guard selection.isEmpty,
                let rawID = persistedLastInspectorDetailEntryIdentity,
                let item = visibleDisplayItems.first(where: { $0.id.rawID == rawID })
            else { return }
            selection.select([item.id])
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
