//
//  MacLibraryView.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/17.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    extension LibraryViewStyle {
        /// The Mac has no Gallery: a shelf paged one poster at a time works against mouse and
        /// trackpad scrolling, and Grid with the inspector already shows the artwork.
        static let macCases: [LibraryViewStyle] = [.list, .grid]
    }

    /// The Mac library window: a sidebar of scopes, the List or Grid, and an inspector that
    /// follows the window's selection (`MacLibrarySelection`).
    ///
    /// The iOS root is `LibraryView`.
    struct MacLibraryView: View {
        @Environment(LibraryStore.self) var store
        @Environment(LibraryBrowseScope.self) var scope
        @Environment(\.windowSceneIdentifier) var windowSceneIdentifier
        @Environment(AppReviewPromptController.self) var appReview
        @Environment(\.openWindow) var openWindow

        @State var actions = LibraryEntryActionState()
        @State var detailSessionStore = EntryDetailSessionStore()
        @State var browse = LibraryBrowseState()
        @State private var showCategoryManager = false
        @State private var searchInitialMode: SearchMode?
        /// The toolbar Find, which narrows this window's scope further.
        @State var find = MacLibraryFind()
        @State var isLibraryFindFocused = false
        @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
        /// This window's selection.
        ///
        /// Only views that depend on it read it (see `MacLibrarySelection`).
        @State var selection = MacLibrarySelection()
        @State private var inspectorLayout = MacLibraryInspectorLayout()
        /// Whether this window shows its inspector, independent of the selection.
        @SceneStorage("libraryInspectorShown") var isInspectorShown = true
        /// This window's selection as newline-separated raw IDs; `nil` until the window first
        /// saves one, so a new window falls back to the last-inspected entry.
        @SceneStorage("librarySelection") var storedSelection: String?
        @SceneStorage("libraryFind") var storedFindText = ""
        /// Find text and selection as the window started or last restored them.
        ///
        /// Scene storage can arrive after the window appears; it applies until the user changes the
        /// value, and after that the live value replaces it.
        @State var lastAppliedFindText = ""
        @State var findAcceptsRestoration = true
        @State var lastAppliedSelection: Set<LibraryEntryIdentity> = []
        @State var selectionAcceptsRestoration = true
        /// The restored selection's raw IDs, reapplied while the restored scope settles.
        @State var pendingRestoredSelection: Set<String>?
        @State var editRequest: MacEntryEditRequest?
        @State var showRefreshAllMetadataAlert = false
        /// The batch the Delete menu command asked to delete, awaiting confirmation.
        @State var pendingBatchDeletion: [AnimeEntry]?

        @AppStorage(.libraryScoringEnabled) var scoringEnabled = true
        @AppStorage(.libraryLastInspectorDetailEntryIdentity)
        var persistedLastInspectorDetailEntryIdentity: String?

        /// This window's view style.
        ///
        /// A Gallery style, seeded from iOS, shows as Grid (see `macCases`).
        var libraryViewStyle: LibraryViewStyle {
            get { scope.viewStyle == .gallery ? .grid : scope.viewStyle }
            nonmutating set { scope.viewStyle = newValue }
        }

        // MARK: - Body

        var body: some View {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                MacLibrarySidebar(openCategoryManager: openCategoryManager)
            } detail: {
                // The inspector is attached to the library column inside the split view: attached
                // outside it, AppKit counted the inspector's width twice in the window's minimum.
                libraryBrowserStack
                    .inspector(isPresented: $isInspectorShown) { inspector }
                    .environment(selection)
                    .environment(\.macLibraryInspectorLayout, inspectorLayout)
                    .navigationSplitViewColumnWidth(min: 520, ideal: 900)
            }
            // Escape clears the selection from anywhere in the window. A focused field or open
            // menu consumes Escape first.
            .onExitCommand { selection.select([]) }
            .modifier(
                MacLibrarySelectionObservers(
                    selection: selection,
                    makeCommandActions: { commandActions },
                    persistSelection: persistSelection
                )
            )
            .onAppear(perform: restoreWindowState)
            .onChange(of: find.text) { _, text in
                if text != lastAppliedFindText { findAcceptsRestoration = false }
                storedFindText = text
            }
            // Scene storage is restored a moment after the window appears.
            .onChange(of: storedFindText) { _, text in restoreFindText(text) }
            .onChange(of: storedSelection) { _, stored in
                guard let stored else { return }
                restoreSelection(fromStored: stored)
            }
            .onAppear { MacLibraryWindows.provideOpenWindow(openWindow) }
            .alert("Refresh all anime infos?", isPresented: $showRefreshAllMetadataAlert) {
                Button("Refresh") { LibraryProfileSettingsActions(store: store).refreshInfos() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This may take considerable time.")
            }
            .alert(
                "Delete Selected Anime?",
                isPresented: Binding(
                    get: { pendingBatchDeletion != nil },
                    set: { if !$0 { pendingBatchDeletion = nil } }
                ),
                presenting: pendingBatchDeletion
            ) { entries in
                Button("Delete", role: .destructive) { deleteEntries(entries) }
                Button("Cancel", role: .cancel) {}
            } message: { entries in
                Text("This will delete \(entries.count) selected anime from your library.")
            }
            .sheet(item: workflowPresentation) { presentation in
                LibraryEntryWorkflowSheet(store: store, presentation: presentation)
            }
            .libraryEntryActionOverlays(
                state: actions,
                deleteEntry: { store.deleteEntry($0) },
                resolveEntry: { store.repository.existingEntry(identity: $0) }
            )
            .libraryWindowBehaviors(
                store: store,
                browse: browse,
                openRoutedEntry: openDetails
            )
        }

        private var workflowPresentation: Binding<LibraryEntryWorkflowPresentation?> {
            let presented = actions.workflowPresentation
            return Binding(
                get: { actions.workflowPresentation },
                set: { presentation in
                    guard presentation == nil, let presented else { return }
                    actions.workflowPresentationDidDismiss(presented)
                }
            )
        }

        private var libraryBrowserStack: some View {
            let displayItems = visibleDisplayItems
            @Bindable var find = find
            return NavigationStack {
                libraryPage(displayItems: displayItems)
                    .toolbar {
                        MacLibraryToolbar(
                            scope: scope,
                            libraryViewStyle: libraryViewStyleBinding,
                            scoringEnabled: scoringEnabled,
                            addAnime: { openSearch(mode: .tmdb) }
                        )
                    }
                    .environment(actions)
                    .searchable(
                        text: $find.text,
                        isPresented: $isLibraryFindFocused,
                        placement: .toolbar,
                        prompt: Text("Find in Library")
                    )
                    .navigationTitle(windowTitle)
                    .modifier(MacLibrarySubtitle(selection: selection, visibleCount: displayItems.count))
                    .animation(LibraryViewTransitions.libraryViewStyleAnimation(), value: libraryViewStyle)
                    .sheet(isPresented: $showCategoryManager) {
                        MacLibraryCategoryManagerSheet { id in scope.macLibraryScope = .category(id) }
                            .presentationDetents([.medium, .large])
                    }
                    .libraryBrowseSearch(
                        browse,
                        scope: scope,
                        appReview: appReview,
                        initialMode: searchInitialMode,
                        reveal: revealSearchTarget
                    )
            }
            // Find narrows the shared list per window, and saved or unsaved edits can change
            // what it matches, so prune against what this window shows, not the store's IDs.
            .onChange(of: displayItems.map(\.id)) { _, shownIDs in
                if !applyPendingRestoredSelection() {
                    selection.prune(keeping: Set(shownIDs))
                }
            }
        }

        @ViewBuilder
        private func libraryPage(displayItems: [LibraryEntryDisplayItem]) -> some View {
            let layoutIDs = displayItems.map(\.id)
            let detailActions = LibraryEntryDetailActions(open: openDetails, edit: editDetails)
            let scrollInputs = LibraryScrollInputs(
                definition: scope.displayDefinition,
                findQuery: find.query,
                request: browse.scrollRequest
            )
            // `libraryViewStyle` never resolves to Gallery on the Mac.
            if libraryViewStyle == .list {
                LibraryEntryPage(id: .list, layoutIDs: layoutIDs) {
                    MacLibraryList(
                        detailActions: detailActions,
                        displayItems: displayItems,
                        bookmark: browse.bookmark,
                        scrollInputs: scrollInputs,
                        highlightRequest: browse.highlightRequest
                    )
                    .safeAreaPadding(.bottom, 20)
                }
            } else {
                LibraryEntryPage(id: .grid, layoutIDs: layoutIDs) {
                    MacLibraryGrid(
                        detailActions: detailActions,
                        displayItems: displayItems,
                        bookmark: browse.bookmark,
                        scrollInputs: scrollInputs,
                        highlightRequest: browse.highlightRequest,
                        isInspectorPresented: isInspectorShown
                    )
                    .safeAreaPadding(.bottom, 20)
                }
            }
        }

        var libraryViewStyleBinding: Binding<LibraryViewStyle> {
            Binding(
                get: { libraryViewStyle },
                set: { style in
                    guard style != libraryViewStyle else { return }
                    // Hold the bookmark before the outgoing page's last callbacks can move it.
                    browse.bookmark.freeze()
                    withAnimation(LibraryViewTransitions.libraryViewStyleAnimation()) {
                        libraryViewStyle = style
                    }
                }
            )
        }

        // MARK: - Actions

        /// The entries this window shows: its scope, narrowed by the toolbar Find.
        var visibleDisplayItems: [LibraryEntryDisplayItem] {
            let query = find.query
            guard !query.isEmpty else { return scope.displayItems }
            let matches = LibrarySearchService.matcher(for: query)
            return scope.displayItems.filter { matches($0.entry) }
        }

        /// Keeps the selection to the entries this window still shows.
        func pruneSelection() {
            selection.prune(keeping: Set(visibleDisplayItems.map(\.id)))
        }

        func openSearch(mode: SearchMode) {
            searchInitialMode = mode
            browse.isSearching = true
        }

        func openDetails(_ entry: AnimeEntry) {
            revealInInspector(entry.libraryIdentity)
        }

        func editDetails(_ entry: AnimeEntry) {
            revealInInspector(entry.libraryIdentity)
            editRequest = MacEntryEditRequest(entryIdentity: entry.libraryIdentity)
        }

        func toggleInspector() {
            withAnimation { isInspectorShown.toggle() }
        }

        func openCategoryManager() {
            showCategoryManager = true
        }

        /// Makes the entry search found or added the selection, shown in the inspector.
        ///
        /// An
        /// explicit reveal wins over this window's Find text.
        private func revealSearchTarget(_ id: LibraryEntryIdentity) {
            if !find.query.isEmpty, !visibleDisplayItems.contains(where: { $0.id == id }) {
                find.clear()
            }
            showInInspector(id)
        }
    }
#endif
