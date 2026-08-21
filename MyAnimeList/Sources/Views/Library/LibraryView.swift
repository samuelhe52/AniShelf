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

struct LibraryView: View {
    // MARK: - Stored Properties

    @Environment(LibraryStore.self) var store
    @State var interaction = LibraryEntryInteractionState()
    @State private var detailSessionStore = EntryDetailSessionStore()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppReviewPromptController.self) var appReview
    @Environment(EpisodeNotificationCoordinator.self) private var episodeNotifications

    // UI state
    @State var isSearching = false
    @State private var showProfileSettings = false
    @State var scrollState = ScrollState()
    @State var newEntriesAddedToggle = false
    @State var highlightedEntryID: LibraryEntryIdentity?
    @State var scrollRequest: LibraryScrollRequest?
    @State private var isShowingBatchDeleteConfirmation = false
    @State private var inspectorDetailWorkspaceState = LibraryInspectorDetailWorkspaceState()

    // Multi-selection snapshot: decouples selection rendering from live store
    // recomputation so toggling items stays cheap. See LibraryView+MultiSelection.
    @State var selectionDisplayItems: [LibraryEntryDisplayItem]?
    @State var selectionEntriesByID: [LibraryEntryIdentity: AnimeEntry] = [:]

    // Persistent UI preference
    @AppStorage(.libraryViewStyle) var libraryViewStyle: LibraryViewStyle = .gallery
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.libraryLastInspectorDetailEntryIdentity)
    private var persistedLastInspectorDetailEntryIdentity: String?

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
        .onChange(
            of: episodeNotifications.pendingRouteEntryIdentityRawID,
            initial: true
        ) { _, entryIdentityRawID in
            handleEpisodeNotificationRoute(entryIdentityRawID)
        }
        .alert(
            notificationWarningTitle,
            isPresented: Binding(
                get: { episodeNotifications.presentedWarning != nil },
                set: { isPresented in
                    if !isPresented {
                        episodeNotifications.dismissPresentedWarning()
                    }
                }
            )
        ) {
            Button("OK") { episodeNotifications.dismissPresentedWarning() }
        } message: {
            Text(notificationWarningMessage)
        }
    }

    private var libraryNavigation: some View {
        let detailSession = detailSessionStore.session(
            for: interaction.presentedDetailEntryID
        )
        let inspectorPresentation = interaction.inspectorPresentation
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
                    detailHostContent(
                        presentation: inspectorPresentation,
                        session: detailSession
                    )
                    .presentationBackground(inspectorPresentation.host.pageBackground)
                    .inspectorColumnWidth(min: 400, ideal: 480, max: 520)
                }
            }
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

    private var libraryNavigationStack: some View {
        NavigationStack {
            ZStack {
                libraryView
            }
            .toolbar {
                LibraryToolbar(
                    store: store,
                    interaction: interaction,
                    libraryViewStyle: libraryViewStyleBinding,
                    scoringEnabled: scoringEnabled,
                    isShowingBatchDeleteConfirmation: $isShowingBatchDeleteConfirmation,
                    isSearching: $isSearching,
                    allFavorite: allFavorite,
                    supportsMultiSelection: supportsMultiSelection,
                    enterMultiSelection: enterMultiSelection,
                    exitMultiSelection: exitMultiSelection,
                    applyBatchAction: applyBatchAction,
                    openProfileSettings: openProfileSettings,
                    checkDuplicate: { store.libraryOnDisplay.map(\.libraryIdentity).contains($0) },
                    processTMDbSearchResults: processTMDbSearchResults,
                    jumpToEntryInLibrary: jumpToEntryInLibrary
                )
            }
            .environment(interaction)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .animation(libraryViewStyleAnimation, value: libraryViewStyle)
            .animation(.default, value: interaction.selectedEntryIDs.isEmpty)
            .sensoryFeedback(.success, trigger: newEntriesAddedToggle)
            .allowsHitTesting(!showProfileSettings)
            .accessibilityHidden(showProfileSettings)
            .alert(
                batchDeleteConfirmationTitle,
                isPresented: $isShowingBatchDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelectedEntries()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(batchDeleteConfirmationMessage)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var libraryView: some View {
        let displayItems = selectionDisplayItems ?? store.libraryDisplayItems
        let layoutIDs = displayItems.map(\.id)
        let detailActions = LibraryEntryDetailActions(
            open: openDetails,
            edit: editDetails
        )

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
                    highlightedEntryID: $highlightedEntryID
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
                    highlightedEntryID: $highlightedEntryID
                )
                .safeAreaPadding(.bottom, 20)
            }
        }
    }

    private var batchDeleteConfirmationTitle: LocalizedStringResource {
        "Delete Selected Anime?"
    }

    private var batchDeleteConfirmationMessage: LocalizedStringResource {
        "This will delete \(interaction.selectedEntryCount) selected anime from your library."
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

    private func openDetails(_ entry: AnimeEntry) {
        prepareAndConfigureDetailHost(for: entry)
        interaction.openDetails(for: entry)
    }

    private func handleEpisodeNotificationRoute(_ entryIdentityRawID: String?) {
        guard let entryIdentityRawID else { return }
        defer { episodeNotifications.consumePendingRoute() }
        guard let entry = store.repository.existingEntry(identityRawID: entryIdentityRawID) else {
            return
        }
        isSearching = false
        showProfileSettings = false
        openDetails(entry)
    }

    private var notificationWarningMessage: LocalizedStringResource {
        switch episodeNotifications.presentedWarning {
        case .queueLimit:
            "iOS could not schedule every next-episode reminder. AniShelf kept the reminders with the nearest airtimes."
        case .schedulingFailure:
            "iOS rejected one or more episode reminders. Existing reminders were restored when possible."
        case nil:
            "Some episode reminders could not be scheduled."
        }
    }

    private var notificationWarningTitle: LocalizedStringResource {
        switch episodeNotifications.presentedWarning {
        case .queueLimit:
            "Notification Limit Reached"
        case .schedulingFailure, nil:
            "Episode Notification Issue"
        }
    }

    private func editDetails(_ entry: AnimeEntry) {
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
        withAnimation(profileSettingsAnimation) {
            showProfileSettings = true
        }
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
        .environment(EpisodeNotificationCoordinator.shared)
}
