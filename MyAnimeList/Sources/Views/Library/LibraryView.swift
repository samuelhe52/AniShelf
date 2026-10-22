//
//  LibraryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import DataProvider
import SwiftUI

#if !os(macOS)
    /// The iOS and iPadOS library root.
    ///
    /// Entry detail opens as a sheet or an iPad inspector,
    /// and batch actions use the multi-selection mode. The Mac root is `MacLibraryView`.
    struct LibraryView: View {
        // MARK: - Stored Properties

        @Environment(LibraryStore.self) var store
        @Environment(LibraryBrowseScope.self) var scope
        @Environment(\.platformHorizontalSizeClass) private var horizontalSizeClass
        @Environment(AppReviewPromptController.self) var appReview

        @State var interaction = LibraryEntryInteractionState()
        @State var detailSessionStore = EntryDetailSessionStore()
        @State var browse = LibraryBrowseState()

        // UI state
        @State private var showProfileSettings = false
        @State private var showCategoryManager = false
        @State private var isReorderingCategories = false
        @State private var inspectorDetailWorkspaceState = LibraryInspectorDetailWorkspaceState()
        /// The detail sheet still on screen, including its dismissal animation.
        @State private var detailSheetOnScreenID: UUID?
        /// The inspector column's presentation, which the system can change on its own across
        /// size-class transitions; `syncInspectorColumn` reconciles it with the detail host.
        @State private var isInspectorColumnPresented = false

        // Persistent UI preference
        @AppStorage(.libraryScoringEnabled) var scoringEnabled = true
        /// The last-inspected entry across windows, which a window without its own saved
        /// inspector entry restores.
        @AppStorage(.libraryLastInspectorDetailEntryIdentity)
        var sharedLastInspectorDetailEntryIdentity: String?
        /// This window's inspector entry; `nil` until the window saves one, and empty once it
        /// closes its inspector.
        @SceneStorage("libraryInspectorDetailEntryIdentity")
        var sceneInspectorDetailEntryIdentity: String?

        /// This window's view style.
        var libraryViewStyle: LibraryViewStyle {
            get { scope.viewStyle }
            nonmutating set { scope.viewStyle = newValue }
        }

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
            .libraryDetailHostCoordination(
                store: store,
                interaction: interaction,
                detailSessionStore: detailSessionStore,
                horizontalSizeClass: horizontalSizeClass,
                isSearching: browse.isSearching,
                isShowingProfileSettings: showProfileSettings,
                workspaceState: $inspectorDetailWorkspaceState,
                persistedLastInspectorDetailEntryIdentity: persistedInspectorDetailEntryIdentity
            )
            .libraryWindowBehaviors(
                store: store,
                browse: browse,
                openRoutedEntry: { entry in
                    showProfileSettings = false
                    openDetails(entry)
                }
            )
            .onChange(of: scope.displayIDs) { pruneSelection() }
        }

        /// This window's inspector entry, falling back to the shared last-inspected entry for a
        /// window that has not saved one; writes update both.
        private var persistedInspectorDetailEntryIdentity: Binding<String?> {
            Binding(
                get: {
                    guard let sceneInspectorDetailEntryIdentity else {
                        return sharedLastInspectorDetailEntryIdentity
                    }
                    return sceneInspectorDetailEntryIdentity.isEmpty ? nil : sceneInspectorDetailEntryIdentity
                },
                set: { identity in
                    sceneInspectorDetailEntryIdentity = identity ?? ""
                    sharedLastInspectorDetailEntryIdentity = identity
                }
            )
        }

        private var libraryNavigation: some View {
            let detailSession = detailSessionStore.session(
                for: interaction.presentedDetailEntryID
            )
            // A size-class change can move detail from the sheet to the inspector while the sheet
            // is still animating away. Presenting the inspector during that dismissal makes SwiftUI
            // report a spurious inspector dismissal and leave an empty column (docs-ai 031), so the
            // inspector waits for the sheet to leave.
            let inspectorPresentation =
                detailSheetOnScreenID != nil ? nil : interaction.inspectorPresentation
            // Keep native inspector content mounted throughout its outgoing transition.
            let inspectorContentPresentation = interaction.detailHostPresentation.flatMap {
                $0.host == .inspector ? $0 : nil
            }
            let retiringPresentationID = interaction.retiringDetailHostPresentationID
            let presentedSheetRoute = interaction.activeSheetRoute
            let activeSheetRoute = Binding<LibraryEntrySheetRoute?>(
                get: { interaction.activeSheetRoute },
                set: { route in
                    guard route == nil, let presentedSheetRoute else { return }
                    interaction.sheetRouteDidDismiss(presentedSheetRoute)
                }
            )

            return
                libraryBrowserStack
                .environment(\.libraryEntryDetailActivation, currentDetailActivation)
                .inspector(
                    isPresented: Binding(
                        get: { isInspectorColumnPresented },
                        set: { isPresented in
                            isInspectorColumnPresented = isPresented
                            syncInspectorColumn(systemPresented: isPresented, presentation: inspectorPresentation)
                        }
                    )
                ) {
                    if let inspectorContentPresentation, let detailSession {
                        detailHostContent(presentation: inspectorContentPresentation, session: detailSession)
                            .presentationBackground(inspectorContentPresentation.host.pageBackground)
                            .inspectorColumnWidth(min: 400, ideal: 480, max: 520)
                    }
                }
                .onChange(of: inspectorPresentation?.id, initial: true) {
                    isInspectorColumnPresented = inspectorPresentation != nil
                }
                .sheet(item: activeSheetRoute) { route in
                    sheetContent(for: route, detailSession: detailSession)
                }
                .task(id: retiringPresentationID) {
                    guard let retiringPresentationID else { return }
                    // Normal migration finishes on native disappearance. Bound the wait in case
                    // SwiftUI drops that callback while rebuilding the presentation hierarchy.
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                    guard interaction.retiringDetailHostPresentationID == retiringPresentationID else { return }
                    if detailSheetOnScreenID == retiringPresentationID {
                        detailSheetOnScreenID = nil
                    }
                    interaction.recoverDetailHostRetirement(
                        retiringPresentationID,
                        migrationBlocked: detailHostMigrationBlocked
                    )
                }
                .libraryEntryActionOverlays(
                    state: interaction.actions,
                    deleteEntry: { entry in
                        scope.deleteEntry(entry) { browse.requestScroll(to: $0) }
                    },
                    resolveEntry: { store.repository.existingEntry(identity: $0) }
                )
        }

        /// Reconciles a presentation change the system made to the inspector column.
        ///
        /// Across a size-class change, such as folding or unfolding iPhone Duo, SwiftUI can
        /// dismiss the inspector before `horizontalSizeClass` reaches this view, and can restore a
        /// column it remembers after the detail has closed. Both are handled on the next main-actor
        /// turn: a dismissal still current after the size-class update closes the detail, and
        /// otherwise the column follows the detail host, so a restored column with no detail
        /// behind it is released instead of staying empty.
        private func syncInspectorColumn(
            systemPresented: Bool,
            presentation: LibraryEntryDetailHostPresentation?
        ) {
            Task { @MainActor in
                let current = detailSheetOnScreenID != nil ? nil : interaction.inspectorPresentation
                if !systemPresented, let presentation, current?.id == presentation.id {
                    interaction.detailHostDidDismiss(presentation)
                    return
                }
                isInspectorColumnPresented = current != nil
            }
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
                    .onAppear { detailSheetOnScreenID = presentation.id }
                    .onDisappear {
                        if detailSheetOnScreenID == presentation.id {
                            detailSheetOnScreenID = nil
                        }
                    }
                }
            case .workflow(let presentation):
                LibraryEntryWorkflowSheet(store: store, presentation: presentation)
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
            .onAppear {
                interaction.detailHostDidAppear(presentation)
            }
            .onDisappear {
                interaction.detailHostDidDisappear(presentation, migrationBlocked: session.blocksHostMigration)
            }
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
                        scope: scope,
                        interaction: interaction,
                        libraryViewStyle: libraryViewStyleBinding,
                        scoringEnabled: scoringEnabled,
                        isSearching: $browse.isSearching,
                        supportsMultiSelection: supportsMultiSelection,
                        showsCategoryStrip: showsCategoryStrip,
                        isReorderingCategories: $isReorderingCategories,
                        enterMultiSelection: enterMultiSelection,
                        exitMultiSelection: exitMultiSelection,
                        applyBatchAction: applyBatchAction,
                        deleteSelectedEntries: deleteSelectedEntries,
                        openProfileSettings: openProfileSettings,
                        openCategoryManager: openCategoryManager
                    )
                }
                .environment(interaction)
                .environment(interaction.actions)
                .navigationTitle("")
                .inlineNavigationTitle()
                .animation(libraryViewStyleAnimation, value: libraryViewStyle)
                .onChange(of: showsCategoryStrip) {
                    if !showsCategoryStrip { isReorderingCategories = false }
                }
                .onChange(of: interaction.isMultiSelecting) {
                    isReorderingCategories = false
                }
                .onChange(of: browse.isSearching) {
                    if browse.isSearching { isReorderingCategories = false }
                }
                .sheet(isPresented: $showCategoryManager) {
                    LibraryCategoryManagerSheet()
                        .presentationDetents([.medium, .large])
                }
                .libraryBrowseSearch(browse, scope: scope, appReview: appReview, reveal: { _ in })
                .allowsHitTesting(!showProfileSettings)
                .accessibilityHidden(showProfileSettings)
            }
        }

        private var showsCategoryStrip: Bool {
            // Stays during multi-selection; switching keeps only still-visible selections.
            // With no categories yet, the toolbar capsule menu stands in for a lone "All" chip.
            store.categoriesEnabled && store.categoryStripEnabled && !store.categories.isEmpty
                && supportsMultiSelection
        }

        // MARK: - Content

        @ViewBuilder
        private var libraryView: some View {
            let displayItems = scope.displayItems
            let layoutIDs = scope.displayIDs
            let detailActions = LibraryEntryDetailActions(
                open: openDetails,
                edit: editDetails
            )

            @Bindable var scrollState = browse.scrollState
            switch libraryViewStyle {
            case .gallery:
                LibraryEntryPage(id: .gallery, layoutIDs: layoutIDs) {
                    LibraryGalleryView(
                        scrolledID: $scrollState.scrolledID,
                        scrollRequest: browse.scrollRequest,
                        detailActions: detailActions
                    )
                    .scenePadding(.vertical)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            case .list:
                LibraryEntryPage(id: .list, layoutIDs: layoutIDs) {
                    LibraryListView(
                        detailActions: detailActions,
                        displayItems: displayItems,
                        scrolledID: $scrollState.scrolledID,
                        scrollRequest: browse.scrollRequest,
                        highlightRequest: browse.highlightRequest
                    )
                    .safeAreaPadding(.bottom, 20)
                }
            case .grid:
                LibraryEntryPage(id: .grid, layoutIDs: layoutIDs) {
                    LibraryGridView(
                        detailActions: detailActions,
                        displayItems: displayItems,
                        scrolledID: $scrollState.scrolledID,
                        scrollRequest: browse.scrollRequest,
                        highlightRequest: browse.highlightRequest,
                        isInspectorPresented: interaction.inspectorPresentation != nil
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
            browse.isSearching
                || showProfileSettings
                || interaction.actions.workflowPresentation != nil
        }

        func openDetails(_ entry: AnimeEntry) {
            prepareAndConfigureDetailHost(for: entry)
            interaction.openDetails(for: entry)
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

        private func openProfileSettings() {
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
    }

    #Preview {
        // dataProvider could be changed to .forPreview for memory-only storage.
        // Uncomment the task below to generate template entries.
        @Previewable let store = LibraryStore(dataProvider: .forPreview)
        LibraryView()
            .onAppear {
                DataProvider.forPreview.generateEntriesForPreview()
            }
            .environment(LibraryBrowseScope(store: store))
            .environment(store)
    }

#endif
