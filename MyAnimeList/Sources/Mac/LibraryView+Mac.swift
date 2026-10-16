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
        /// The library window's sidebar and detail column. `detail` already carries the inspector:
        /// attached outside the split view, AppKit counted its width twice in the window's minimum.
        func macLibrarySplitView(detail: some View) -> some View {
            NavigationSplitView(columnVisibility: $macSidebarVisibility) {
                MacLibrarySidebar(openCategoryManager: openCategoryManager)
            } detail: {
                detail
                    .navigationSplitViewColumnWidth(min: 520, ideal: 900)
            }
            // Escape ends a batch selection from anywhere in the window, including List and the
            // batch panel; the grid also clears a single selection itself. A focused field or
            // open menu consumes Escape first.
            .onExitCommand {
                if interaction.isMultiSelecting { applyMacSelection([]) }
            }
            .focusedSceneValue(\.macLibraryCommands, macCommandActions)
            .onChange(of: windowSceneIdentifier, initial: true) { _, identifier in
                MacLibraryWindows.register(identifier, openWindow: openWindow)
            }
            .alert("Refresh all anime infos?", isPresented: $showRefreshAllMetadataAlert) {
                Button("Refresh") { LibraryProfileSettingsActions(store: store).refreshInfos() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This may take considerable time.")
            }
            .alert(LocalizedStringResource("Delete Selected Anime?"), isPresented: $showDeleteSelectionAlert) {
                Button("Delete", role: .destructive, action: deleteSelectedEntries)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    LocalizedStringResource(
                        "This will delete \(interaction.selectedEntryCount) selected anime from your library."))
            }
        }

        var isMacBatchInspectorShown: Bool {
            interaction.isMultiSelecting && !isBatchInspectorHidden
        }

        var macBatchSelectionPanel: some View {
            let ids = selectionLayoutIDs ?? visibleDisplayItems.map(\.id)
            let selected = ids.filter(interaction.selectedEntryIDs.contains).compactMap {
                selectionEntriesByID[$0]
            }
            return MacBatchSelectionPanel(
                store: store,
                interaction: interaction,
                selectedEntries: selected,
                lastClickedID: macSelectionAnchor,
                entriesByID: selectionEntriesByID,
                scoringEnabled: scoringEnabled,
                applyBatchAction: applyBatchAction,
                deleteSelectedEntries: deleteSelectedEntries,
                hideInspector: hideBatchInspector
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

        var macWindowSubtitle: Text {
            if interaction.isMultiSelecting {
                Text("\(interaction.selectedEntryCount) Selected")
            } else {
                Text("\(visibleDisplayItems.count) Anime")
            }
        }

        var macCommandActions: MacLibraryCommandActions {
            MacLibraryCommandActions(
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
                isMultiSelecting: interaction.isMultiSelecting,
                selectAll: selectAllDisplayedEntries,
                clearSelection: exitMultiSelection,
                openCategoryManager: openCategoryManager,
                refreshAllMetadata: { showRefreshAllMetadataAlert = true },
                targetEntry: commandTargetEntry,
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
                deleteSelection: { showDeleteSelectionAlert = true }
            )
        }

        /// Applies a click from a view that does not select natively, such as the grid.
        func handleMacClick(
            on id: LibraryEntryIdentity,
            _ click: MacSelectionClick,
            layoutIDs: [LibraryEntryIdentity]
        ) {
            let current: Set<LibraryEntryIdentity> =
                if interaction.isMultiSelecting {
                    interaction.selectedEntryIDs
                } else {
                    interaction.inspectorPresentation.map { [$0.entryIdentity] } ?? []
                }

            switch click {
            case .replace:
                macSelectionAnchor = id
                applyMacSelection([id])
            case .toggle:
                macSelectionAnchor = id
                applyMacSelection(current.symmetricDifference([id]))
            case .extend:
                guard let anchor = macSelectionAnchor ?? current.first,
                    let anchorIndex = layoutIDs.firstIndex(of: anchor),
                    let index = layoutIDs.firstIndex(of: id)
                else {
                    macSelectionAnchor = id
                    applyMacSelection([id])
                    return
                }
                let range = min(anchorIndex, index)...max(anchorIndex, index)
                applyMacSelection(Set(layoutIDs[range]))
            }
        }

        /// One selected entry is inspected; several become the batch selection.
        func applyMacSelection(_ ids: Set<LibraryEntryIdentity>) {
            // A single selection, however it was made, is where a ⇧-click range starts.
            if ids.count <= 1 { macSelectionAnchor = ids.first }
            switch ids.count {
            case 0:
                if interaction.isMultiSelecting {
                    exitMultiSelection()
                }
                if interaction.inspectorPresentation != nil {
                    interaction.dismissDetails()
                }
            case 1:
                if interaction.isMultiSelecting {
                    exitMultiSelection()
                }
                if let id = ids.first, let entry = store.repository.existingEntry(identity: id) {
                    openDetails(entry)
                }
            default:
                if !interaction.isMultiSelecting {
                    // Establish the replacement content before clearing the detail. Clearing
                    // detail first publishes a closed inspector between animation transactions,
                    // and its dismissal callback hides the newly opened batch panel.
                    withAnimation(LibraryViewTransitions.selectionModeAnimation()) {
                        isBatchInspectorHidden = false
                        enterMultiSelection()
                        interaction.selectedEntryIDs = ids
                        interaction.dismissDetails()
                    }
                } else {
                    interaction.selectedEntryIDs = ids
                }
            }
        }

        /// A scope change that hides the inspected entry closes the inspector, as a selection
        /// does when a Finder window changes folders. Edits that move the entry out of scope
        /// keep it, so changing its status in the inspector does not close it.
        func dismissInspectorOutsideScope() {
            guard !interaction.isMultiSelecting,
                let id = interaction.inspectorPresentation?.entryIdentity,
                !visibleDisplayItems.contains(where: { $0.id == id })
            else { return }
            interaction.dismissDetails()
        }

        func selectAllDisplayedEntries() {
            let ids = Set(visibleDisplayItems.map(\.id))
            guard ids.count > 1 else { return }
            applyMacSelection(ids)
        }
    }
#endif
