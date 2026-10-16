//
//  LibraryView+Mac.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/15.
//

#if os(macOS)
    import AppKit
    import DataProvider
    import SwiftUI

    extension LibraryView {
        /// The library window's sidebar and detail column. `detail` already carries the inspector:
        /// attached outside the split view, AppKit counted its width twice in the window's minimum.
        func macLibrarySplitView(detail: some View) -> some View {
            NavigationSplitView {
                MacLibrarySidebar(openCategoryManager: openCategoryManager)
            } detail: {
                // The column holds the library and the inspector, so its minimum grows while the
                // inspector is open. A library squeezed narrower than its toolbar put AppKit into an
                // endless layout loop, and narrow rows clip under the inspector.
                detail
                    .navigationSplitViewColumnWidth(
                        min: interaction.inspectorPresentation == nil ? 520 : 1000,
                        // A changing ideal would resize the window every time the inspector opens.
                        ideal: 900
                    )
            }
            .focusedSceneValue(\.macLibraryCommands, macCommandActions)
            .onChange(of: windowSceneIdentifier, initial: true) { _, identifier in
                MacLibraryWindows.register(identifier, openWindow: openWindow)
            }
            .onChange(of: interaction.inspectorPresentation != nil) { _, isPresented in
                guard isPresented else { return }
                keepWindowWidthForInspector()
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
                Text("\(store.libraryOnDisplay.count) Anime")
            }
        }

        var macCommandActions: MacLibraryCommandActions {
            MacLibraryCommandActions(
                addAnime: { openSearch(mode: .tmdb) },
                findInLibrary: { openSearch(mode: .library) },
                viewStyle: Binding(
                    get: { libraryViewStyle },
                    set: { style in
                        withAnimation(LibraryViewTransitions.libraryViewStyleAnimation()) {
                            libraryViewStyle = style
                        }
                    }
                ),
                isInspectorPresented: interaction.inspectorPresentation != nil,
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
                guard supportsMultiSelection else { return }
                if !interaction.isMultiSelecting {
                    interaction.dismissDetails()
                    enterMultiSelection()
                }
                interaction.selectedEntryIDs = ids
            }
        }

        /// A scope change that hides the inspected entry closes the inspector, as a selection
        /// does when a Finder window changes folders. Edits that move the entry out of scope
        /// keep it, so changing its status in the inspector does not close it.
        func dismissInspectorOutsideScope() {
            guard !interaction.isMultiSelecting,
                let id = interaction.inspectorPresentation?.entryIdentity,
                !store.libraryDisplayItems.contains(where: { $0.id == id })
            else { return }
            interaction.dismissDetails()
        }

        /// AppKit widens the window by the inspector's width when it opens, even past the
        /// screen edge. Keep the user's width unless the column's larger minimum needs more,
        /// and never exceed the visible screen.
        func keepWindowWidthForInspector() {
            guard
                let window = NSApplication.shared.windows.first(where: {
                    $0.sceneIdentifier == windowSceneIdentifier
                })
            else { return }
            let widthBeforeInspector = window.frame.width
            // A resize the user makes meanwhile wins over the correction.
            let userResize = MacUserResizeFlag(window: window)
            Task { @MainActor in
                defer { userResize.stop() }
                // AppKit resizes in steps after the inspector appears; settle after each one.
                for delay in [350, 900] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !userResize.didResize, !window.inLiveResize else { return }
                    var frame = window.frame
                    let visible = window.screen?.visibleFrame ?? frame
                    let width = min(max(widthBeforeInspector, window.minSize.width), visible.width)
                    guard abs(frame.width - width) > 0.5 else { continue }
                    frame.size.width = width
                    frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - width)
                    window.setFrame(frame, display: true, animate: false)
                }
            }
        }

        func selectAllDisplayedEntries() {
            guard supportsMultiSelection else { return }
            let ids = Set(store.libraryDisplayItems.map(\.id))
            guard ids.count > 1 else { return }
            applyMacSelection(ids)
        }
    }

    /// Records whether the user live-resizes a window while it is being observed.
    @MainActor
    final class MacUserResizeFlag {
        private(set) var didResize = false
        private var observer: NSObjectProtocol?

        init(window: NSWindow) {
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willStartLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.didResize = true }
            }
        }

        func stop() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
#endif
