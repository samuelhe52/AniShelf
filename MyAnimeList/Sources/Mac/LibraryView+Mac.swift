//
//  LibraryView+Mac.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/15.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    extension LibraryView {
        /// The library window's sidebar and detail column. `detail` already carries the inspector.
        func macLibrarySplitView(detail: some View) -> some View {
            NavigationSplitView(columnVisibility: $macSidebarVisibility) {
                MacLibrarySidebar(openCategoryManager: openCategoryManager)
            } detail: {
                detail
                    .navigationSplitViewColumnWidth(min: 520, ideal: 900)
            }
            // Escape clears the selection from anywhere in the window. A focused field or open
            // menu consumes Escape first.
            .onExitCommand { macSelection.select([]) }
            .modifier(
                MacLibrarySelectionObservers(
                    selection: macSelection,
                    makeCommandActions: { macCommandActions },
                    persistSelection: persistMacSelection
                )
            )
            .onAppear(perform: restoreMacSelection)
            .onChange(of: windowSceneIdentifier, initial: true) { _, identifier in
                MacLibraryWindows.register(identifier, openWindow: openWindow)
            }
            .alert("Refresh all anime infos?", isPresented: $showRefreshAllMetadataAlert) {
                Button("Refresh") { LibraryProfileSettingsActions(store: store).refreshInfos() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This may take considerable time.")
            }
            .alert(
                LocalizedStringResource("Delete Selected Anime?"),
                isPresented: Binding(
                    get: { macPendingBatchDeletion != nil },
                    set: { if !$0 { macPendingBatchDeletion = nil } }
                ),
                presenting: macPendingBatchDeletion
            ) { entries in
                Button("Delete", role: .destructive) { deleteMacEntries(entries) }
                Button("Cancel", role: .cancel) {}
            } message: { entries in
                Text(LocalizedStringResource("This will delete \(entries.count) selected anime from your library."))
            }
        }

        /// The inspector's content, which follows this window's selection.
        var macInspector: some View {
            MacLibraryInspector(
                store: store,
                selection: macSelection,
                displayItems: visibleDisplayItems,
                detailSessionStore: detailSessionStore,
                editRequest: $macEditRequest,
                scoringEnabled: scoringEnabled,
                applyBatchAction: applyMacBatchAction,
                deleteEntries: deleteMacEntries,
                isPresented: $isMacInspectorShown
            )
        }

        var macWindowTitle: Text {
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
        var macCommandActions: MacLibraryCommandActions {
            let selectionCount = macSelection.ids.count
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
                isInspectorPresented: isMacInspectorShown,
                toggleInspector: toggleInspector,
                hasSelection: selectionCount > 0,
                hasBatchSelection: selectionCount > 1,
                selectAll: selectAllDisplayedEntries,
                clearSelection: { macSelection.select([]) },
                openCategoryManager: openCategoryManager,
                refreshAllMetadata: { showRefreshAllMetadataAlert = true },
                targetEntry: macSelection.single.flatMap { store.repository.existingEntry(identity: $0) },
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
                shareEntry: { interaction.presentWorkflow(.sharing($0.libraryIdentity)) },
                switchPoster: { interaction.presentWorkflow(.posterSelection($0.libraryIdentity)) },
                deleteEntry: { interaction.prepareDeletion(for: $0) },
                deleteSelection: { macPendingBatchDeletion = selectedMacEntries }
            )
        }

        /// The selected entries in layout order.
        private var selectedMacEntries: [AnimeEntry] {
            let ids = macSelection.ids
            return visibleDisplayItems.filter { ids.contains($0.id) }.map(\.entry)
        }

        /// Selects an entry and shows it in the inspector, as double-click, Show Details, and
        /// an airing reminder do. Scope and Find give way when they hide the entry.
        func revealInMacInspector(_ id: LibraryEntryIdentity) {
            if !visibleDisplayItems.contains(where: { $0.id == id }) {
                libraryFindQuery = ""
                if store.activeCategoryID != nil,
                    !store.libraryOnDisplay.contains(where: { $0.libraryIdentity == id })
                {
                    store.activeCategoryID = nil
                }
                if !store.canRevealEntry(id) { store.resetFiltersToReveal(id) }
            }
            showInMacInspector(id)
            requestLibraryScroll(to: id)
        }

        /// Makes an entry the selection and shows the inspector.
        func showInMacInspector(_ id: LibraryEntryIdentity) {
            macSelection.select([id])
            if !isMacInspectorShown {
                withAnimation { isMacInspectorShown = true }
            }
        }

        func selectAllDisplayedEntries() {
            macSelection.select(Set(visibleDisplayItems.map(\.id)))
        }

        func applyMacBatchAction(_ entries: [AnimeEntry], _ action: LibraryBatchAction) {
            guard !entries.isEmpty else { return }
            // A desktop selection stays until the user changes it, as in Finder, so several
            // actions can apply to it. Entries the action moves out of scope leave it.
            action.apply(to: entries)
            refreshSelectionDisplayItemsIfNeeded()
            if entries.count >= 3 { appReview.record(.multiSelectAction) }
        }

        func deleteMacEntries(_ entries: [AnimeEntry]) {
            guard !entries.isEmpty else { return }
            let deleted = Set(entries.map(\.libraryIdentity))
            let scrollTarget = visibleDisplayItems.first { !deleted.contains($0.id) }?.id
            guard store.deleteEntries(entries) else { return }
            requestLibraryScroll(to: scrollTarget)
            refreshSelectionDisplayItemsIfNeeded()
        }

        /// Remembers a single selection as the last-inspected entry, as iPad does for its
        /// inspector, so the next window opens on it.
        private func persistMacSelection(_ ids: Set<LibraryEntryIdentity>) {
            if ids.isEmpty {
                persistedLastInspectorDetailEntryIdentity = nil
            } else if ids.count == 1, let id = ids.first {
                persistedLastInspectorDetailEntryIdentity = id.rawID
            }
        }

        private func restoreMacSelection() {
            guard macSelection.isEmpty,
                let rawID = persistedLastInspectorDetailEntryIdentity,
                let item = visibleDisplayItems.first(where: { $0.id.rawID == rawID })
            else { return }
            macSelection.select([item.id])
        }
    }

    /// The window state that depends on the selection, kept out of `LibraryView`'s body so a
    /// click does not recompute the library's display items.
    fileprivate struct MacLibrarySelectionObservers: ViewModifier {
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
