//
//  MacLibraryView.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
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
    /// follows the window's selection (`MacLibrarySelection`). The iOS root is `LibraryView`.
    struct MacLibraryView: View {
        @Environment(LibraryStore.self) var store
        @Environment(\.windowSceneIdentifier) var windowSceneIdentifier
        @Environment(AppReviewPromptController.self) var appReview
        @Environment(\.openWindow) var openWindow

        @State var actions = LibraryEntryActionState()
        @State var detailSessionStore = EntryDetailSessionStore()
        @State var browse = LibraryBrowseState()
        @State private var showCategoryManager = false
        @State private var searchInitialMode: SearchMode?
        /// The toolbar Find text. Per window, unlike the sidebar scope.
        @State var libraryFindQuery = ""
        @State var isLibraryFindFocused = false
        @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
        /// This window's selection. Only views that depend on it read it (see `MacLibrarySelection`).
        @State var selection = MacLibrarySelection()
        /// Whether this window shows its inspector, independent of the selection.
        @SceneStorage("libraryInspectorShown") var isInspectorShown = true
        @State var editRequest: MacEntryEditRequest?
        @State var showRefreshAllMetadataAlert = false
        /// The batch the Delete menu command asked to delete, awaiting confirmation.
        @State var pendingBatchDeletion: [AnimeEntry]?

        @AppStorage(.libraryViewStyle) private var storedLibraryViewStyle: LibraryViewStyle = .gallery
        @AppStorage(.libraryScoringEnabled) var scoringEnabled = true
        @AppStorage(.libraryLastInspectorDetailEntryIdentity)
        var persistedLastInspectorDetailEntryIdentity: String?

        /// The library's view style. A stored Gallery preference shows as Grid (see `macCases`).
        var libraryViewStyle: LibraryViewStyle {
            get { storedLibraryViewStyle == .gallery ? .grid : storedLibraryViewStyle }
            nonmutating set { storedLibraryViewStyle = newValue }
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
            .onAppear(perform: restoreSelection)
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
                    get: { pendingBatchDeletion != nil },
                    set: { if !$0 { pendingBatchDeletion = nil } }
                ),
                presenting: pendingBatchDeletion
            ) { entries in
                Button("Delete", role: .destructive) { deleteEntries(entries) }
                Button("Cancel", role: .cancel) {}
            } message: { entries in
                Text(LocalizedStringResource("This will delete \(entries.count) selected anime from your library."))
            }
            .sheet(item: workflowPresentation) { presentation in
                LibraryEntryWorkflowSheet(store: store, presentation: presentation)
            }
            .libraryEntryActionOverlays(
                state: actions,
                deleteEntry: { entry in
                    store.deleteEntry(entry) { browse.requestScroll(to: $0) }
                },
                resolveEntry: { store.repository.existingEntry(identity: $0) }
            )
            .onChange(of: libraryFindQuery) {
                pruneSelection()
            }
            .libraryWindowBehaviors(
                store: store,
                browse: browse,
                openRoutedEntry: openDetails,
                scopeDidChange: pruneSelection
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
            return NavigationStack {
                libraryPage(displayItems: displayItems)
                .toolbar {
                    MacLibraryToolbar(
                        store: store,
                        libraryViewStyle: libraryViewStyleBinding,
                        scoringEnabled: scoringEnabled,
                        addAnime: { openSearch(mode: .tmdb) }
                    )
                }
                .environment(actions)
                .searchable(
                    text: $libraryFindQuery,
                    isPresented: $isLibraryFindFocused,
                    placement: .toolbar,
                    prompt: Text("Find in Library")
                )
                .navigationTitle(windowTitle)
                .modifier(MacLibrarySubtitle(selection: selection, visibleCount: displayItems.count))
                .animation(LibraryViewTransitions.libraryViewStyleAnimation(), value: libraryViewStyle)
                .sheet(isPresented: $showCategoryManager) {
                    LibraryCategoryManagerSheet()
                        .presentationDetents([.medium, .large])
                }
                .libraryBrowseSearch(
                    browse,
                    store: store,
                    appReview: appReview,
                    initialMode: searchInitialMode,
                    reveal: revealSearchTarget
                )
            }
        }

        @ViewBuilder
        private func libraryPage(displayItems: [LibraryEntryDisplayItem]) -> some View {
            @Bindable var scrollState = browse.scrollState
            let layoutIDs = displayItems.map(\.id)
            let detailActions = LibraryEntryDetailActions(open: openDetails, edit: editDetails)
            // `libraryViewStyle` never resolves to Gallery on the Mac.
            if libraryViewStyle == .list {
                LibraryEntryPage(id: .list, layoutIDs: layoutIDs) {
                    MacLibraryList(
                        detailActions: detailActions,
                        displayItems: displayItems,
                        scrolledID: $scrollState.scrolledID,
                        scrollRequest: browse.scrollRequest,
                        highlightRequest: browse.highlightRequest
                    )
                    .safeAreaPadding(.bottom, 20)
                }
            } else {
                LibraryEntryPage(id: .grid, layoutIDs: layoutIDs) {
                    MacLibraryGrid(
                        detailActions: detailActions,
                        displayItems: displayItems,
                        scrolledID: $scrollState.scrolledID,
                        scrollRequest: browse.scrollRequest,
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
                    withAnimation(LibraryViewTransitions.libraryViewStyleAnimation()) {
                        libraryViewStyle = style
                    }
                }
            )
        }

        // MARK: - Actions

        /// The entries this window shows: the shared scope, narrowed by the toolbar Find.
        var visibleDisplayItems: [LibraryEntryDisplayItem] {
            let query = libraryFindQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return store.libraryDisplayItems }
            let matches = LibrarySearchService.matcher(for: query)
            return store.libraryDisplayItems.filter { matches($0.entry) }
        }

        /// Keeps the selection to the entries still shown after a library, scope, or Find change.
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

        /// Makes the entry search found or added the selection, shown in the inspector. An
        /// explicit reveal wins over this window's Find text.
        private func revealSearchTarget(_ id: LibraryEntryIdentity) {
            if !libraryFindQuery.isEmpty, !visibleDisplayItems.contains(where: { $0.id == id }) {
                libraryFindQuery = ""
            }
            showInInspector(id)
        }
    }
#endif
