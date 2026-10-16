//
//  LibraryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
import LibrarySync
import SwiftUI

struct LibraryScrollRequest: Equatable {
    // Keep repeated explicit requests to the same entry observable.
    let token = UUID()
    let entryID: LibraryEntryIdentity?
}

struct LibraryHighlightRequest: Equatable {
    // A fresh token restarts the pulse even when the same entry is requested again.
    let token = UUID()
    let entryID: LibraryEntryIdentity

    /// Long enough for a row created late in the jump scroll to finish its pulse.
    static let lifetime: Duration = .seconds(2.5)

    func trigger(for entryID: LibraryEntryIdentity) -> UUID? {
        self.entryID == entryID ? token : nil
    }
}

struct LibraryView: View {
    // MARK: - Stored Properties

    @Environment(LibraryStore.self) var store
    @Environment(\.platformHorizontalSizeClass) private var horizontalSizeClass
    @Environment(\.windowSceneIdentifier) var windowSceneIdentifier
    @Environment(AppReviewPromptController.self) var appReview
    private let airingReminders = AiringReminderCoordinator.shared

    @State var interaction = LibraryEntryInteractionState()
    @State private var detailSessionStore = EntryDetailSessionStore()

    // UI state
    @State var isSearching = false
    @State private var showProfileSettings = false
    @State private var showCategoryManager = false
    @State private var isReorderingCategories = false
    @State var scrollState = ScrollState()
    @State var newEntriesAddedToggle = false
    @State var highlightRequest: LibraryHighlightRequest?
    // A jump from search waits for the sheet to finish dismissing so it is not hidden behind it.
    @State var isSearchSheetOnScreen = false
    @State var pendingJumpEntryID: LibraryEntryIdentity?
    @State var scrollRequest: LibraryScrollRequest?
    @State private var inspectorDetailWorkspaceState = LibraryInspectorDetailWorkspaceState()

    // Multi-selection snapshot: decouples selection rendering from live store
    // recomputation so toggling items stays cheap. See LibraryView+MultiSelection.
    @State var selectionDisplayItems: [LibraryEntryDisplayItem]?
    @State var selectionLayoutIDs: [LibraryEntryIdentity]?
    @State var selectionEntriesByID: [LibraryEntryIdentity: AnimeEntry] = [:]

    // Persistent UI preference
    @AppStorage(.libraryViewStyle) private var storedLibraryViewStyle: LibraryViewStyle = .gallery
    /// The library's view style. The Mac has no Gallery: a shelf paged one poster at a time
    /// works against mouse and trackpad scrolling, and Grid with the inspector already shows
    /// the artwork. A stored Gallery preference shows as Grid there.
    var libraryViewStyle: LibraryViewStyle {
        get {
            #if os(macOS)
                storedLibraryViewStyle == .gallery ? .grid : storedLibraryViewStyle
            #else
                storedLibraryViewStyle
            #endif
        }
        nonmutating set { storedLibraryViewStyle = newValue }
    }
    @AppStorage(.libraryScoringEnabled) var scoringEnabled = true
    @AppStorage(.libraryLastInspectorDetailEntryIdentity)
    private var persistedLastInspectorDetailEntryIdentity: String?

    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
        @Environment(\.openWindow) var openWindow
        @State var searchInitialMode: SearchMode?
        /// The toolbar Find text. Per window, unlike the sidebar scope.
        @State var libraryFindQuery = ""
        @State var isLibraryFindFocused = false
        /// Hides the batch-selection panel the inspector shows during a batch selection.
        @State var isBatchInspectorHidden = false
        @State var macSidebarVisibility: NavigationSplitViewVisibility = .automatic
        @State var macSelectionAnchor: LibraryEntryIdentity?
        @State var showRefreshAllMetadataAlert = false
        @State var showDeleteSelectionAlert = false
    #endif

    // MARK: - Body

    var body: some View {
        ZStack {
            libraryNavigation
                .opacity(showProfileSettings ? 0 : 1)
                .allowsHitTesting(!showProfileSettings)
                .accessibilityHidden(showProfileSettings)

            if showProfileSettings {
                LibraryProfileSettingsView {
                    closeProfileSettings()
                }
                .transition(profileSettingsTransition)
                .zIndex(1)
            }
        }
        .animation(profileSettingsAnimation, value: showProfileSettings)
        .onChange(of: scoringEnabled) { _, newValue in
            guard !newValue, store.groupStrategy == .score else { return }
            store.groupStrategy = .none
        }
        .libraryDetailHostCoordination(
            store: store,
            interaction: interaction,
            detailSessionStore: detailSessionStore,
            horizontalSizeClass: horizontalSizeClass,
            isSearching: isSearching,
            isShowingProfileSettings: showProfileSettings,
            workspaceState: $inspectorDetailWorkspaceState,
            persistedLastInspectorDetailEntryIdentity: $persistedLastInspectorDetailEntryIdentity
        )
        .onChange(of: store.libraryRevision) {
            refreshSelectionDisplayItemsIfNeeded()
        }
        .onChange(of: store.filters) {
            refreshSelectionDisplayItemsIfNeeded()
            #if os(macOS)
                dismissInspectorOutsideScope()
            #endif
        }
        .onChange(of: store.groupStrategy) {
            refreshSelectionDisplayItemsIfNeeded()
        }
        .onChange(of: store.sortStrategy) {
            refreshSelectionDisplayItemsIfNeeded()
        }
        .onChange(of: store.sortReversed) {
            refreshSelectionDisplayItemsIfNeeded()
        }
        .onChange(of: store.hideDroppedByDefault) {
            refreshSelectionDisplayItemsIfNeeded()
        }
        #if os(macOS)
            .onChange(of: libraryFindQuery) {
                refreshSelectionDisplayItemsIfNeeded()
                dismissInspectorOutsideScope()
            }
        #endif
        .onChange(of: store.activeCategoryID) {
            // onChange does not reliably inherit the switch's animation, and
            // the selection snapshot is what the list renders while selecting.
            withAnimation(.snappy) {
                refreshSelectionDisplayItemsIfNeeded()
            }
            #if os(macOS)
                dismissInspectorOutsideScope()
            #endif
        }
        .task(id: highlightRequest?.token) {
            // Expire the request so rows recreated later by scrolling or filtering do not pulse again.
            guard highlightRequest != nil,
                (try? await Task.sleep(for: LibraryHighlightRequest.lifetime)) != nil
            else { return }
            highlightRequest = nil
        }
        .onChange(of: airingReminders.pendingRoute, initial: true) {
            handleAiringReminderRoute()
        }
        .onChange(of: windowSceneIdentifier) {
            handleAiringReminderRoute()
        }
        // A route targeting the closed window falls back to the remaining windows.
        .onOtherWindowSceneClosed(than: windowSceneIdentifier) {
            handleAiringReminderRoute()
        }
        .alert(
            airingReminderWarningTitle,
            isPresented: Binding(
                get: { airingReminders.presentedWarning != nil },
                set: { isPresented in
                    if !isPresented {
                        airingReminders.dismissPresentedWarning()
                    }
                }
            )
        ) {
            Button("OK") { airingReminders.dismissPresentedWarning() }
        } message: {
            Text(airingReminderWarningMessage)
        }
        .sheet(isPresented: duplicateRepairPresented) {
            LibraryDuplicateRepairSheet(store: store)
                .presentationDetents([.large])
                .presentationSizing(.page)
                .macSheetFrame(width: 760, height: 640)
        }
    }

    private var duplicateRepairPresented: Binding<Bool> {
        Binding(
            get: { store.requiresDuplicateRepair },
            set: { _ in }
        )
    }

    /// Hosts entry detail in the trailing inspector. On the Mac it is attached to the library
    /// column inside the split view: attached outside it, AppKit counted the inspector's width
    /// twice in the window's minimum size.
    private var entryInspector: LibraryEntryInspectorModifier {
        #if os(macOS)
            let batchContent: AnyView? = isMacBatchInspectorShown ? AnyView(macBatchSelectionPanel) : nil
            let isBatchShown = { isMacBatchInspectorShown }
            let batchDidHide = { hideBatchInspector() }
        #else
            let batchContent: AnyView? = nil
            let isBatchShown = { false }
            let batchDidHide = {}
        #endif
        return LibraryEntryInspectorModifier(
            interaction: interaction,
            detailSession: detailSessionStore.session(for: interaction.presentedDetailEntryID),
            content: { presentation, session in
                AnyView(detailHostContent(presentation: presentation, session: session))
            },
            batchContent: batchContent,
            isBatchShown: isBatchShown,
            batchDidHide: batchDidHide
        )
    }

    private var libraryNavigation: some View {
        let detailSession = detailSessionStore.session(
            for: interaction.presentedDetailEntryID
        )
        let presentedSheetRoute = interaction.activeSheetRoute
        let detailActivation = currentDetailActivation
        let activeSheetRoute = Binding<LibraryEntrySheetRoute?>(
            get: { interaction.activeSheetRoute },
            set: { route in
                guard route == nil, let presentedSheetRoute else { return }
                interaction.sheetRouteDidDismiss(presentedSheetRoute)
            }
        )

        return
            libraryNavigationStack
            .environment(\.libraryEntryDetailActivation, detailActivation)
            #if !os(macOS)
                .modifier(entryInspector)
            #endif
            .sheet(item: activeSheetRoute) { route in
                sheetContent(for: route, detailSession: detailSession)
            }
            .libraryEntryInteractionOverlays(
                state: interaction,
                deleteEntry: { entry in
                    store.deleteEntry(entry) { requestLibraryScroll(to: $0) }
                },
                resolveEntry: { store.repository.existingEntry(identity: $0) }
            )
    }

    @ViewBuilder
    private func sheetContent(
        for route: LibraryEntrySheetRoute,
        detailSession: EntryDetailSession?
    ) -> some View {
        switch route {
        case .detail(let presentation):
            if let detailSession {
                detailHostContent(
                    presentation: presentation,
                    session: detailSession
                )
                .presentationBackground(presentation.host.pageBackground)
            }
        case .workflow(let presentation):
            workflowContent(for: presentation)
        }
    }

    private func detailHostContent(
        presentation: LibraryEntryDetailHostPresentation,
        session: EntryDetailSession
    ) -> some View {
        NavigationStack {
            EntryDetailView(
                session: session,
                detailHost: presentation.host,
                onClose: { _ in
                    interaction.dismissDetails(
                        ifHostPresentationID: presentation.id
                    )
                },
                editingRequestID: detailEditingRequestID(
                    for: presentation.entryIdentity,
                    hostPresentationID: presentation.id
                ),
                onEditingRequestHandled: { requestID in
                    interaction.consumeDetailEditRequest(
                        requestID,
                        fromHostPresentationID: presentation.id
                    )
                },
                hostPresentationID: presentation.id,
                isCurrentHostPresentation: {
                    interaction.isCurrentDetailHostPresentation($0)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func workflowContent(for presentation: LibraryEntryWorkflowPresentation) -> some View {
        if let entry = store.repository.existingEntry(
            identity: presentation.workflow.entryIdentity
        ) {
            switch presentation.workflow {
            case .posterSelection:
                NavigationStack {
                    PosterSelectionView(
                        tmdbID: entry.tmdbID,
                        type: entry.type,
                        originalPosterLanguageCode: entry.originalLanguageCode
                            ?? entry.parentSeriesEntry?.originalLanguageCode
                    ) { url in
                        if url != entry.posterURL || !entry.usingCustomPoster {
                            entry.updateCustomPosterURL(url)
                        }
                    }
                    .navigationTitle("Pick a poster")
                }
            case .sharing:
                AnimeSharingSheet(entry: entry)
            }
        }
    }

    @ViewBuilder
    private var libraryNavigationStack: some View {
        #if os(macOS)
            macLibrarySplitView(detail: libraryBrowserStack.modifier(entryInspector))
        #else
            libraryBrowserStack
        #endif
    }

    private var libraryBrowserStack: some View {
        NavigationStack {
            ZStack {
                libraryView
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsCategoryStrip {
                    LibraryCategoryStrip(
                        openCategoryManager: openCategoryManager,
                        allowsCategoryActions: !interaction.isMultiSelecting,
                        isReordering: $isReorderingCategories
                    )
                }
            }
            // The strip can appear from paths without an animation transaction, such as the
            // first category created from the selection menu or arriving through sync.
            .animation(.snappy, value: showsCategoryStrip)
            .toolbar {
                LibraryToolbar(
                    store: store,
                    interaction: interaction,
                    libraryViewStyle: libraryViewStyleBinding,
                    scoringEnabled: scoringEnabled,
                    isSearching: $isSearching,
                    selectionEntriesByID: selectionEntriesByID,
                    supportsMultiSelection: supportsMultiSelection,
                    showsCategoryStrip: showsCategoryStrip,
                    isReorderingCategories: $isReorderingCategories,
                    enterMultiSelection: enterMultiSelection,
                    exitMultiSelection: exitMultiSelection,
                    applyBatchAction: applyBatchAction,
                    deleteSelectedEntries: deleteSelectedEntries,
                    openProfileSettings: openProfileSettings,
                    openCategoryManager: openCategoryManager,
                    addAnime: { openSearch(mode: .tmdb) },
                    isInspectorPresented: isInspectorShown,
                    toggleInspector: toggleInspector
                )
            }
            .environment(interaction)
            #if os(macOS)
                .searchable(
                    text: $libraryFindQuery,
                    isPresented: $isLibraryFindFocused,
                    placement: .toolbar,
                    prompt: Text("Find in Library")
                )
                .navigationTitle(macWindowTitle)
                .navigationSubtitle(macWindowSubtitle)
            #else
                .navigationTitle("")
                .inlineNavigationTitle()
            #endif
            .animation(libraryViewStyleAnimation, value: libraryViewStyle)
            .sensoryFeedback(.success, trigger: newEntriesAddedToggle)
            .onChange(of: showsCategoryStrip) {
                if !showsCategoryStrip { isReorderingCategories = false }
            }
            .onChange(of: interaction.isMultiSelecting) {
                isReorderingCategories = false
                #if os(macOS)
                    // Each new batch selection shows its panel again.
                    if !interaction.isMultiSelecting { isBatchInspectorHidden = false }
                #endif
            }
            .onChange(of: isSearching) {
                if isSearching {
                    isReorderingCategories = false
                    isSearchSheetOnScreen = true
                }
            }
            .sheet(isPresented: $showCategoryManager) {
                LibraryCategoryManagerSheet()
                    .presentationDetents([.medium, .large])
            }
            .librarySearchSheet(
                isPresented: $isSearching,
                checkDuplicate: store.containsEntry,
                canRevealEntry: store.canRevealEntry,
                resetFiltersToReveal: store.resetFiltersToReveal,
                processTMDbSearchResults: processTMDbSearchResults,
                jumpToEntryInLibrary: jumpToEntryInLibrary,
                onDismiss: searchSheetDidDismiss,
                initialMode: macSearchInitialMode
            )
            .allowsHitTesting(!showProfileSettings)
            .accessibilityHidden(showProfileSettings)
        }
    }

    private var showsCategoryStrip: Bool {
        #if os(macOS)
            // The sidebar lists the categories on the Mac.
            return false
        #endif
        // Stays during multi-selection; switching keeps only still-visible selections.
        // With no categories yet, the toolbar capsule menu stands in for a lone "All" chip.
        store.categoriesEnabled && store.categoryStripEnabled && !store.categories.isEmpty
            && supportsMultiSelection
    }

    // MARK: - Content

    @ViewBuilder
    private var libraryView: some View {
        let displayItems = selectionDisplayItems ?? visibleDisplayItems
        let layoutIDs = selectionLayoutIDs ?? displayItems.map(\.id)
        #if os(macOS)
            let detailActions = LibraryEntryDetailActions(
                open: openDetails,
                edit: editDetails,
                click: { id, click in handleMacClick(on: id, click, layoutIDs: layoutIDs) },
                select: applyMacSelection
            )
        #else
            let detailActions = LibraryEntryDetailActions(
                open: openDetails,
                edit: editDetails
            )
        #endif

        switch libraryViewStyle {
        case .gallery:
            libraryViewPage(id: .gallery, layoutIDs: layoutIDs) {
                LibraryGalleryView(
                    scrolledID: $scrollState.scrolledID,
                    scrollRequest: scrollRequest,
                    detailActions: detailActions
                )
                .scenePadding(.vertical)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        case .list:
            libraryViewPage(id: .list, layoutIDs: layoutIDs) {
                LibraryListView(
                    detailActions: detailActions,
                    displayItems: displayItems,
                    scrolledID: $scrollState.scrolledID,
                    scrollRequest: scrollRequest,
                    highlightRequest: highlightRequest
                )
                .safeAreaPadding(.bottom, 20)
            }
        case .grid:
            libraryViewPage(id: .grid, layoutIDs: layoutIDs) {
                LibraryGridView(
                    detailActions: detailActions,
                    displayItems: displayItems,
                    scrolledID: $scrollState.scrolledID,
                    scrollRequest: scrollRequest,
                    highlightRequest: highlightRequest,
                    inspectorIsVisible: isInspectorShown
                )
                .safeAreaPadding(.bottom, 20)
            }
        }
    }

    private var libraryViewStyleBinding: Binding<LibraryViewStyle> {
        Binding(
            get: { libraryViewStyle },
            set: { newValue in
                guard newValue != libraryViewStyle else { return }
                withAnimation(libraryViewStyleAnimation) {
                    libraryViewStyle = newValue
                }
            }
        )
    }

    private var libraryViewStyleAnimation: Animation {
        LibraryViewTransitions.libraryViewStyleAnimation()
    }

    private var libraryViewTransition: AnyTransition {
        LibraryViewTransitions.libraryViewTransition()
    }

    private var profileSettingsAnimation: Animation {
        LibraryViewTransitions.profileSettingsAnimation()
    }

    private var profileSettingsTransition: AnyTransition {
        LibraryViewTransitions.profileSettingsTransition()
    }

    // MARK: - Entry Actions

    private var detailHostPolicy: LibraryEntryDetailHostPolicy {
        LibraryEntryDetailHostPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    private var currentDetailActivation: LibraryEntryDetailActivation {
        guard let committedHost = interaction.detailHostPresentation?.host else {
            return detailHostPolicy.activation
        }
        return committedHost == .inspector ? .singleTap : .userPreference
    }

    private var detailHostMigrationBlocked: Bool {
        detailSessionStore.session(
            for: interaction.presentedDetailEntryID
        )?.blocksHostMigration == true
    }

    private var isRootPresentationActive: Bool {
        isSearching
            || showProfileSettings
            || interaction.workflowPresentation != nil
    }

    func openDetails(_ entry: AnimeEntry) {
        endMacBatchForEntryRequest()
        prepareAndConfigureDetailHost(for: entry)
        interaction.openDetails(for: entry)
    }

    private func handleAiringReminderRoute() {
        // A window whose scene is already disconnected is being torn down and must not consume the route.
        if let windowSceneIdentifier, !WindowScenes.canReceiveRoute(windowSceneIdentifier) {
            return
        }
        guard
            let entryIdentityRawID = airingReminders.claimPendingRoute(
                forSceneIdentifier: windowSceneIdentifier,
                isSceneConnected: WindowScenes.canReceiveRoute
            )
        else { return }
        guard let entry = store.repository.existingEntry(identityRawID: entryIdentityRawID) else {
            return
        }
        isSearching = false
        showProfileSettings = false
        openDetails(entry)
    }

    private var airingReminderWarningMessage: LocalizedStringResource {
        airingReminders.presentedWarning?.localizedMessage
            ?? "Some reminders could not be scheduled."
    }

    private var airingReminderWarningTitle: LocalizedStringResource {
        airingReminders.presentedWarning?.localizedTitle
            ?? "Reminder Scheduling Issue"
    }

    func editDetails(_ entry: AnimeEntry) {
        endMacBatchForEntryRequest()
        prepareAndConfigureDetailHost(for: entry)
        interaction.setEditingEntry(entry)
    }

    /// On the Mac a batch panel occupies the inspector, so a request for one entry, such as
    /// a context-menu Edit during a batch, ends the batch to show that entry.
    private func endMacBatchForEntryRequest() {
        #if os(macOS)
            guard interaction.isMultiSelecting else { return }
            exitMultiSelection()
        #endif
    }

    private func prepareAndConfigureDetailHost(for entry: AnimeEntry) {
        LibraryDetailHostCoordination.prepareDetailSession(
            for: entry,
            detailSessionStore: detailSessionStore,
            repository: store.repository
        )
        LibraryDetailHostCoordination.updateDetailHost(
            interaction: interaction,
            detailSessionStore: detailSessionStore,
            desiredHost: detailHostPolicy.host,
            migrationBlocked: detailHostMigrationBlocked,
            rootPresentationActive: isRootPresentationActive
        )
    }

    private func detailEditingRequestID(
        for identity: LibraryEntryIdentity,
        hostPresentationID: UUID
    ) -> UUID? {
        guard interaction.detailEditRequest?.entryIdentity == identity,
            interaction.detailEditRequest?.hostPresentationID == hostPresentationID
        else { return nil }
        return interaction.detailEditRequest?.id
    }

    func requestLibraryScroll(to entryID: LibraryEntryIdentity?) {
        scrollState.scrolledID = entryID
        scrollRequest = LibraryScrollRequest(entryID: entryID)
    }

    private func openProfileSettings() {
        #if os(macOS)
            openSettings()
            return
        #endif
        isReorderingCategories = false
        withAnimation(profileSettingsAnimation) {
            showProfileSettings = true
        }
    }

    func openCategoryManager() {
        isReorderingCategories = false
        showCategoryManager = true
    }

    private func closeProfileSettings() {
        withAnimation(profileSettingsAnimation) {
            showProfileSettings = false
        }
    }

    private func libraryViewPage<Content: View>(
        id: LibraryViewStyle,
        layoutIDs: [LibraryEntryIdentity],
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(id)
            .animation(.default, value: layoutIDs)
            .transition(libraryViewTransition)
    }

    // MARK: - Types

    enum LibraryViewStyle: String, CaseIterable {
        case gallery
        case list
        case grid

        /// The styles this platform offers; the Mac has no Gallery (see `libraryViewStyle`).
        static var platformCases: [LibraryViewStyle] {
            #if os(macOS)
                [.list, .grid]
            #else
                allCases
            #endif
        }

        var nameKey: LocalizedStringKey {
            switch self {
            case .gallery: "Gallery"
            case .list: "List"
            case .grid: "Grid"
            }
        }

        var systemImageName: String {
            switch self {
            case .gallery: "photo.on.rectangle.angled"
            case .list: "list.bullet.rectangle.portrait"
            case .grid: "rectangle.grid.3x2.fill"
            }
        }

    }
}

#Preview {
    // dataProvider could be changed to .forPreview for memory-only storage.
    // Uncomment the task below to generate template entries.
    @Previewable let store = LibraryStore(dataProvider: .forPreview)
    LibraryView()
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(store)
}

fileprivate struct LibraryEntryInspectorModifier: ViewModifier {
    let interaction: LibraryEntryInteractionState
    let detailSession: EntryDetailSession?
    let content: (LibraryEntryDetailHostPresentation, EntryDetailSession) -> AnyView
    /// The Mac batch-selection panel, shown in place of entry detail; always `nil` on iOS.
    let batchContent: AnyView?
    /// Read current batch visibility when reconciling the native presentation state.
    let isBatchShown: () -> Bool
    let batchDidHide: () -> Void

    #if os(macOS)
        @State private var macInspectorPresented = false
    #endif

    func body(content base: Content) -> some View {
        let inspectorPresentation = interaction.inspectorPresentation
        #if os(macOS)
            base
                .inspector(isPresented: $macInspectorPresented) {
                    Group {
                        if let batchContent {
                            batchContent
                        } else if let inspectorPresentation, let detailSession {
                            content(inspectorPresentation, detailSession)
                                .presentationBackground(inspectorPresentation.host.pageBackground)
                        }
                    }
                    .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
                }
                .onChange(of: isBatchShown() || inspectorPresentation != nil, initial: true) { _, shown in
                    withAnimation(.smooth(duration: 0.3)) { macInspectorPresented = shown }
                }
                .onChange(of: macInspectorPresented) { old, shown in
                    guard old, !shown else { return }
                    if isBatchShown() {
                        batchDidHide()
                    } else if let inspectorPresentation {
                        interaction.detailHostDidDismiss(inspectorPresentation)
                    }
                }
        #else
            base
                .inspector(
                    isPresented: Binding(
                        get: {
                            if isBatchShown() { return true }
                            guard let inspectorPresentation else { return false }
                            return interaction.inspectorPresentation?.id == inspectorPresentation.id
                        },
                        set: { isPresented in
                            guard !isPresented else { return }
                            if isBatchShown() {
                                batchDidHide()
                                return
                            }
                            guard let inspectorPresentation else { return }
                            interaction.detailHostDidDismiss(inspectorPresentation)
                        }
                    )
                ) {
                    if let inspectorPresentation, let detailSession {
                        content(inspectorPresentation, detailSession)
                            .presentationBackground(inspectorPresentation.host.pageBackground)
                            .inspectorColumnWidth(min: 400, ideal: 480, max: 520)
                    }
                }
        #endif
    }
}
