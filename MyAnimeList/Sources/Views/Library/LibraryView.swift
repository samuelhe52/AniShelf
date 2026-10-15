//
//  LibraryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
import LibrarySync
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

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
    @AppStorage(.libraryViewStyle) var libraryViewStyle: LibraryViewStyle = .gallery
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.libraryLastInspectorDetailEntryIdentity)
    private var persistedLastInspectorDetailEntryIdentity: String?

    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
        @Environment(\.openWindow) private var openWindow
        @State var searchInitialMode: SearchMode?
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
        #if os(macOS)
            .onChange(of: windowSceneIdentifier, initial: true) { _, identifier in
                MacLibraryWindows.register(identifier, openWindow: openWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                let closedIdentifier = (notification.object as? NSWindow)?.sceneIdentifier
                guard closedIdentifier != windowSceneIdentifier else { return }
                Task { @MainActor in handleAiringReminderRoute() }
            }
        #else
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) {
                notification in
                // The disconnecting window still receives this before it is purged; only survivors retry.
                let disconnectedSceneIdentifier = (notification.object as? UIScene)?.session.persistentIdentifier
                guard disconnectedSceneIdentifier != windowSceneIdentifier else { return }
                // A route targeting the closed window falls back to the remaining windows. Retry on the
                // next turn so the disconnected scene has left `connectedScenes`.
                Task { @MainActor in handleAiringReminderRoute() }
            }
        #endif
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
        LibraryEntryInspectorModifier(
            interaction: interaction,
            detailSession: detailSessionStore.session(for: interaction.presentedDetailEntryID),
            content: { presentation, session in
                AnyView(detailHostContent(presentation: presentation, session: session))
            }
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
            NavigationSplitView {
                MacLibrarySidebar(openCategoryManager: openCategoryManager)
            } detail: {
                // The column holds the library and the inspector, so its minimum grows while the
                // inspector is open. A library squeezed narrower than its toolbar put AppKit into an
                // endless layout loop, and narrow rows clip under the inspector.
                libraryBrowserStack
                    .modifier(entryInspector)
                    .navigationSplitViewColumnWidth(
                        min: interaction.inspectorPresentation == nil ? 520 : 1000,
                        // A changing ideal would resize the window every time the inspector opens.
                        ideal: 900
                    )
            }
            .focusedSceneValue(\.macLibraryCommands, macCommandActions)
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
                    checkDuplicate: store.containsEntry,
                    processTMDbSearchResults: processTMDbSearchResults,
                    jumpToEntryInLibrary: jumpToEntryInLibrary,
                    onSearchDismissed: searchSheetDidDismiss,
                    searchInitialMode: macSearchInitialMode,
                    addAnime: { openSearch(mode: .tmdb) },
                    isInspectorPresented: interaction.inspectorPresentation != nil,
                    toggleInspector: toggleInspector
                )
            }
            .environment(interaction)
            #if os(macOS)
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
        let displayItems = selectionDisplayItems ?? store.libraryDisplayItems
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
                    highlightRequest: highlightRequest
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
        prepareAndConfigureDetailHost(for: entry)
        interaction.openDetails(for: entry)
    }

    private func handleAiringReminderRoute() {
        // A window whose scene is already disconnected is being torn down and must not consume the route.
        if let windowSceneIdentifier, !Self.isSceneConnected(windowSceneIdentifier) {
            return
        }
        guard
            let entryIdentityRawID = airingReminders.claimPendingRoute(
                forSceneIdentifier: windowSceneIdentifier,
                isSceneConnected: Self.isSceneConnected
            )
        else { return }
        guard let entry = store.repository.existingEntry(identityRawID: entryIdentityRawID) else {
            return
        }
        isSearching = false
        showProfileSettings = false
        openDetails(entry)
    }

    private static func isSceneConnected(_ identifier: String) -> Bool {
        #if os(macOS)
            NSApplication.shared.windows.contains { $0.sceneIdentifier == identifier && $0.isVisible }
        #else
            UIApplication.shared.connectedScenes.contains {
                $0.session.persistentIdentifier == identifier
            }
        #endif
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
        prepareAndConfigureDetailHost(for: entry)
        interaction.setEditingEntry(entry)
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

    func body(content base: Content) -> some View {
        let inspectorPresentation = interaction.inspectorPresentation
        base
            .inspector(
                isPresented: Binding(
                    get: {
                        guard let inspectorPresentation else { return false }
                        return interaction.inspectorPresentation?.id == inspectorPresentation.id
                    },
                    set: { isPresented in
                        guard !isPresented, let inspectorPresentation else { return }
                        interaction.detailHostDidDismiss(inspectorPresentation)
                    }
                )
            ) {
                if let inspectorPresentation,
                    let detailSession
                {
                    content(inspectorPresentation, detailSession)
                        .presentationBackground(inspectorPresentation.host.pageBackground)
                        #if os(macOS)
                            // Narrower than iPad so the library column keeps room for its toolbar.
                            .inspectorColumnWidth(min: 340, ideal: 400, max: 560)
                        #else
                            .inspectorColumnWidth(min: 400, ideal: 480, max: 520)
                        #endif
                }
            }
    }
}
