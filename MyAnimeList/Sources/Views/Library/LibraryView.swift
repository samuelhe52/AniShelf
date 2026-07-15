//
//  LibraryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import Collections
import DataProvider
import LibrarySync
import SwiftData
import SwiftUI

// MARK: - Environment Keys

extension EnvironmentValues {
    @Entry var toggleFavorite: (AnimeEntry) -> Void = { _ in }
}

struct LibraryView: View {
    // MARK: - Stored Properties

    @Environment(LibraryStore.self) private var store
    @State private var interaction = LibraryEntryInteractionState()
    @State private var detailSessionStore = EntryDetailSessionStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppReviewPromptController.self) private var appReview

    // UI state
    @State private var isSearching = false
    @State private var showProfileSettings = false
    @State private var scrollState = ScrollState()
    @State private var newEntriesAddedToggle = false
    @State private var highlightedEntryID: Int?
    @State private var isShowingBatchDeleteConfirmation = false
    @State private var selectionDisplayItems: [LibraryEntryDisplayItem]?
    @State private var selectionEntriesByID: [Int: AnimeEntry] = [:]
    @State private var didRestorePresentedDetail = false

    // Persistent UI preference
    @AppStorage(.libraryViewStyle) var libraryViewStyle: LibraryViewStyle = .gallery
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.libraryPresentedDetailEntryIdentity)
    private var persistedPresentedDetailEntryIdentity: String?

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
        .onAppear {
            updateDetailHost(source: .initial)
            restorePresentedDetailIfNeeded()
        }
        .onChange(of: horizontalSizeClass) {
            updateDetailHost(source: .horizontalSizeClass)
        }
        .onChange(of: libraryViewStyle) {
            updateDetailHost(source: .displayMode)
        }
        .onChange(of: detailHostMigrationBlocked) { _, isBlocked in
            guard !isBlocked else { return }
            interaction.reconcileDetailHostIfPossible(migrationBlocked: false)
        }
        .onInteractiveResizeChange { isResizing in
            interaction.interactiveResizeDidChange(
                isResizing,
                migrationBlocked: detailHostMigrationBlocked
            )
        }
        .onChange(of: interaction.presentedDetailEntryID) { _, identity in
            persistedPresentedDetailEntryIdentity = identity?.rawID
        }
        #if DEBUG
            .onAppear {
                openDebugDetailIfRequested()
            }
        #endif
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
            .environment(\.libraryEntryOpenDetailAction, openDetails)
            .environment(\.libraryEntryEditAction, editDetails)
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
                    .inspectorColumnWidth(min: 400, ideal: 480, max: 520)
                }
            }
            .sheet(item: activeSheetRoute) { route in
                sheetContent(for: route, detailSession: detailSession)
            }
            .libraryEntryInteractionOverlays(
                state: interaction,
                deleteEntry: { entry in
                    store.deleteEntry(entry) { scrollState.scrolledID = $0 }
                },
                resolveEntry: { store.repository.existingEntry(identity: $0) }
            )
            .onChange(of: interaction.presentedDetailEntryID, initial: true) { _, identity in
                synchronizePresentedDetail(identity)
            }
            .onChange(of: store.libraryRevision) {
                refreshSelectionDisplayItemsIfNeeded()
                synchronizePresentedDetail(interaction.presentedDetailEntryID)
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
        .environment(\.libraryEntryDetailHost, presentation.host)
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
            .toolbar { topBarContent }
            .toolbar { bottomBarContent }
            .environment(\.toggleFavorite, toggleFavorite)
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

        switch libraryViewStyle {
        case .gallery:
            libraryViewPage(id: .gallery) {
                LibraryGalleryView(
                    scrolledID: $scrollState.scrolledID
                )
                .scenePadding(.vertical)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        case .list:
            libraryViewPage(id: .list) {
                LibraryListView(
                    displayItems: displayItems,
                    scrolledID: $scrollState.scrolledID,
                    highlightedEntryID: $highlightedEntryID
                )
                .safeAreaPadding(.bottom, 20)
            }
        case .grid:
            libraryViewPage(id: .grid) {
                LibraryGridView(
                    displayItems: displayItems,
                    scrolledID: $scrollState.scrolledID,
                    highlightedEntryID: $highlightedEntryID
                )
                .safeAreaPadding(.bottom, 20)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var bottomBarContent: some ToolbarContent {
        if interaction.isMultiSelecting {
            ToolbarItem(placement: .bottomBar) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isShowingBatchDeleteConfirmation = true
                }
                .disabled(interaction.selectedEntryIDs.isEmpty)
                .tint(.red)
            }
            ToolbarItemGroup(placement: .status) {
                Menu("Mark Status", systemImage: "checklist") {
                    ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                        Button {
                            applyBatchAction(.watchStatus(status))
                        } label: {
                            Label(status.localizedStringResource, systemImage: status.batchActionSystemImage)
                        }
                    }
                }
                .disabled(interaction.selectedEntryIDs.isEmpty)

                Button(
                    allFavorite ? "Unfavorite" : "Favorite",
                    systemImage: allFavorite ? "heart.slash.fill" : "heart.fill"
                ) {
                    applyBatchAction(.favorite(allFavorite ? false : true))
                }
                .disabled(interaction.selectedEntryIDs.isEmpty)
                .animation(.snappy(duration: 0.3), value: allFavorite)
            }
            ToolbarItem(placement: .bottomBar) {
                batchActionsMenu
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                Picker("View Style", selection: libraryViewStyleBinding) {
                    ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                        Label(style.nameKey, systemImage: style.systemImageName).tag(style)
                    }
                }
                .labelsHidden()
            }
            ToolbarItem(placement: .status) {
                libraryBrowseSummaryMenu
            }
            ToolbarItem(placement: .bottomBar) {
                searchButton
            }
        }
    }

    @ToolbarContentBuilder
    private var topBarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            LibraryNavigationTitleCapsule(
                count:
                    interaction.isMultiSelecting
                    ? interaction.selectedEntryCount : store.libraryOnDisplay.count
            )
        }
        if supportsMultiSelection && !interaction.isMultiSelecting {
            // Counterbalances the trailing controls so the principal title sits visually left of center.
            ToolbarItem(placement: .topBarTrailing) {
                Color.clear
                    .frame(width: 10, height: 0)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if interaction.isMultiSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exitMultiSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(Text("Dismiss Selection"))
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                if supportsMultiSelection {
                    Button(action: enterMultiSelection) {
                        Text("Select").font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Anime Multi-selection"))
                    .padding(.leading, 3)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                profileSettingsButton
                    .padding(.trailing, 3)
            }
        }
    }

    @ViewBuilder
    private var batchActionsMenu: some View {
        Menu {
            Button("Track Dates", systemImage: "calendar.badge.checkmark") {
                applyBatchAction(.dateTracking(true))
            }
            Button("Hide Dates", systemImage: "calendar.badge.minus") {
                applyBatchAction(.dateTracking(false))
            }

            if scoringEnabled {
                Menu("Score", systemImage: "star") {
                    ForEach(Array(AnimeEntry.validScoreRange), id: \.self) { score in
                        Button("\(score)/5") {
                            applyBatchAction(.score(score))
                        }
                    }
                    Button("Clear Score", systemImage: "xmark.circle") {
                        applyBatchAction(.score(nil))
                    }
                }
            }
        } label: {
            Label("Actions", systemImage: "ellipsis")
        }
        .disabled(interaction.selectedEntryIDs.isEmpty)
    }

    @ViewBuilder
    private var libraryBrowseSummaryMenu: some View {
        @Bindable var store = store

        Menu {
            Section("Group By") {
                Picker(
                    "Group By",
                    systemImage: "square.grid.2x2",
                    selection: groupStrategyBinding
                ) {
                    ForEach(availableGroupStrategies, id: \.self) { strategy in
                        Text(strategy.localizedStringResource).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Sort") {
                Toggle(
                    "Reversed",
                    systemImage: "arrow.counterclockwise.circle",
                    isOn: $store.sortReversed
                )
                Picker(
                    "Sort",
                    systemImage: "arrow.up.arrow.down",
                    selection: $store.sortStrategy
                ) {
                    ForEach(LibraryStore.AnimeSortStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.localizedStringResource).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Filter") {
                Toggle(
                    "All",
                    isOn: .init(
                        get: { store.filters.isEmpty },
                        set: {
                            if $0 {
                                store.filters.removeAll()
                            }
                        }
                    )
                )
                ForEach(LibraryStore.AnimeFilter.typeCases, id: \.self) { filter in
                    filterToggle(for: filter)
                }
                Menu("Watch Status") {
                    ForEach(LibraryStore.AnimeFilter.watchStatusCases, id: \.self) { filter in
                        filterToggle(for: filter)
                    }
                }
                filterToggle(for: .favorited)
            }
        } label: {
            LibraryToolbarSummaryCapsule(
                primary: filterSummaryResource
            )
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var availableGroupStrategies: [LibraryStore.LibraryGroupStrategy] {
        if scoringEnabled {
            LibraryStore.LibraryGroupStrategy.allCases
        } else {
            LibraryStore.LibraryGroupStrategy.allCases.filter { $0 != .score }
        }
    }

    private var supportsMultiSelection: Bool {
        libraryViewStyle == .list || libraryViewStyle == .grid
    }

    private var selectedEntries: [AnimeEntry] {
        interaction.selectedEntryIDs.compactMap { selectionEntriesByID[$0] }
    }

    private var allFavorite: Bool {
        !interaction.selectedEntryIDs.isEmpty && selectedEntries.allSatisfy(\.favorite)
    }

    private var batchDeleteConfirmationTitle: LocalizedStringResource {
        "Delete Selected Anime?"
    }

    private var batchDeleteConfirmationMessage: LocalizedStringResource {
        "This will delete \(interaction.selectedEntryCount) selected anime from your library."
    }

    private var groupStrategyBinding: Binding<LibraryStore.LibraryGroupStrategy> {
        Binding(
            get: {
                if !scoringEnabled, store.groupStrategy == .score {
                    return .none
                }
                return store.groupStrategy
            },
            set: { store.groupStrategy = $0 }
        )
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

    private var libraryViewStyleAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.34, extraBounce: 0.12)
    }

    private var selectionModeAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.26, extraBounce: 0.06)
    }

    private var libraryViewTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: LibraryViewTransitionModifier(
                    opacity: 0,
                    scale: 0.975,
                    blurRadius: 8,
                    yOffset: 14
                ),
                identity: LibraryViewTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    blurRadius: 0,
                    yOffset: 0
                )
            ),
            removal: .modifier(
                active: LibraryViewTransitionModifier(
                    opacity: 0,
                    scale: 1.018,
                    blurRadius: 5,
                    yOffset: -10
                ),
                identity: LibraryViewTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    blurRadius: 0,
                    yOffset: 0
                )
            )
        )
    }

    private var profileSettingsAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)
    }

    private var profileSettingsTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: LibraryProfileSettingsBlendModifier(
                    opacity: 0,
                    blurRadius: 22
                ),
                identity: LibraryProfileSettingsBlendModifier(
                    opacity: 1,
                    blurRadius: 0
                )
            ),
            removal: .modifier(
                active: LibraryProfileSettingsBlendModifier(
                    opacity: 0,
                    blurRadius: 14
                ),
                identity: LibraryProfileSettingsBlendModifier(
                    opacity: 1,
                    blurRadius: 0
                )
            )
        )
    }

    // MARK: - Search

    private var searchButton: some View {
        Button("Search...", systemImage: "magnifyingglass") { isSearching = true }
            .sheet(isPresented: $isSearching) {
                NavigationStack {
                    SearchPage(
                        onDuplicateTapped: { tappedID in
                            isSearching = false
                            scrollState.scrolledID = tappedID
                            highlightedEntryID = tappedID
                        },
                        checkDuplicate: { store.libraryOnDisplay.map(\.tmdbID).contains($0) },
                        processTMDbSearchResults: processTMDbSearchResults,
                        jumpToEntryInLibrary: { tmdbID in
                            isSearching = false
                            scrollState.scrolledID = tmdbID
                            highlightedEntryID = tmdbID
                        }
                    )
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
    }

    // MARK: - Profile Settings

    private var profileSettingsButton: some View {
        Button {
            openProfileSettings()
        } label: {
            LibraryProfileLauncherBadge()
        }
        .accessibilityLabel(Text("Open Library Profile"))
    }

    private var activeFilters: [LibraryStore.AnimeFilter] {
        LibraryStore.AnimeFilter.allCases.filter { store.filters.contains($0) }
    }

    private var filterSummaryResource: LocalizedStringResource {
        switch activeFilters.count {
        case 0:
            return "All"
        case 1:
            return filterSummaryResource(for: activeFilters[0])
        default:
            return "\(activeFilters.count) Filters"
        }
    }

    private func filterSummaryResource(
        for filter: LibraryStore.AnimeFilter
    ) -> LocalizedStringResource {
        switch filter.id {
        case LibraryStore.AnimeFilter.favorited.id:
            return "Favorites"
        case LibraryStore.AnimeFilter.watched.id:
            return "Watched"
        case LibraryStore.AnimeFilter.planToWatch.id:
            return "Planned"
        case LibraryStore.AnimeFilter.watching.id:
            return "Watching"
        case LibraryStore.AnimeFilter.dropped.id:
            return "Dropped"
        default:
            return filter.name
        }
    }

    // MARK: - Entry Actions

    private var detailHostPolicy: LibraryEntryDetailHostPolicy {
        LibraryEntryDetailHostPolicy(
            mode: libraryViewStyle.detailMode,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    private var currentDetailActivation: LibraryEntryDetailActivation {
        guard let committedHost = interaction.detailHostPresentation?.host else {
            return detailHostPolicy.activation
        }
        return committedHost == .inspector ? .singleTap : .userPreference
    }

    private var detailHostMigrationBlocked: Bool {
        interaction.workflowPresentation != nil
            || detailSessionStore.session(
                for: interaction.presentedDetailEntryID
            )?.blocksHostMigration == true
    }

    private func updateDetailHost(source: LibraryEntryDetailHostChangeSource) {
        interaction.requestDetailHost(
            detailHostPolicy.host,
            source: source,
            migrationBlocked: detailHostMigrationBlocked
        )
    }

    private func prepareDetailSession(for entry: AnimeEntry) {
        detailSessionStore.synchronizePresentedDetail(
            identity: entry.syncIdentity,
            repository: store.repository,
            resolveEntry: { identity in
                identity == entry.syncIdentity
                    ? entry : store.repository.existingEntry(identity: identity)
            }
        )
    }

    private func openDetails(_ entry: AnimeEntry) {
        prepareDetailSession(for: entry)
        updateDetailHost(source: .initial)
        interaction.openDetails(for: entry)
    }

    private func editDetails(_ entry: AnimeEntry) {
        prepareDetailSession(for: entry)
        updateDetailHost(source: .initial)
        interaction.setEditingEntry(entry)
    }

    private func detailEditingRequestID(
        for identity: LibraryEntrySyncIdentity,
        hostPresentationID: UUID
    ) -> UUID? {
        guard interaction.detailEditRequest?.entryIdentity == identity,
            interaction.detailEditRequest?.hostPresentationID == hostPresentationID
        else { return nil }
        return interaction.detailEditRequest?.id
    }

    private func toggleFavorite(_ entry: AnimeEntry) {
        store.repository.toggleFavorite(entry)
    }

    private func synchronizePresentedDetail(_ identity: LibraryEntrySyncIdentity?) {
        let didResolveDetail = detailSessionStore.synchronizePresentedDetail(
            identity: identity,
            repository: store.repository,
            resolveEntry: { store.repository.existingEntry(identity: $0) }
        )
        if identity != nil, !didResolveDetail {
            interaction.dismissDetails()
        }
    }

    private func restorePresentedDetailIfNeeded() {
        guard !didRestorePresentedDetail else { return }
        didRestorePresentedDetail = true

        guard interaction.presentedDetailEntryID == nil,
            let identityRawID = persistedPresentedDetailEntryIdentity,
            !identityRawID.isEmpty
        else { return }

        guard let entry = store.repository.existingEntry(identityRawID: identityRawID),
            entry.onDisplay
        else {
            persistedPresentedDetailEntryIdentity = nil
            interaction.dismissDetails()
            return
        }

        prepareDetailSession(for: entry)
        interaction.openDetails(for: entry)
    }

    #if DEBUG
        private func openDebugDetailIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-OpenFirstLibraryDetail"),
                interaction.presentedDetailEntryID == nil,
                let entry = store.libraryOnDisplay.first
            else { return }

            scrollState.scrolledID = entry.tmdbID
            openDetails(entry)
        }
    #endif

    private func jumpToEntryInLibrary(withID id: Int) {
        scrollState.scrolledID = id
        highlightedEntryID = id
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

    private func processTMDbSearchResults(
        _ results: OrderedSet<SearchResult>,
        origin: SearchSubmissionOrigin
    ) {
        isSearching = false
        Task {
            ToastCenter.global.loadingMessage = .message("Loading...")
            let success = await store.newEntryFromSearchResults(results)
            if success {
                appReview.record(origin == .regular ? .regularSearchAdd : .batchSearchAdd)
                ToastCenter.global.loadingMessage = nil
                withAnimation {
                    newEntriesAddedToggle.toggle()
                    if let id = results.first?.tmdbID {
                        scrollState.scrolledID = id
                        highlightedEntryID = id
                    }
                }
            }
        }
    }

    private func applyBatchAction(_ action: LibraryBatchAction) {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }

        action.apply(to: entries)
        exitMultiSelection()
        if entries.count >= 3 {
            appReview.record(.multiSelectAction)
        }
    }

    private func deleteSelectedEntries() {
        let entries = selectedEntries
        guard !entries.isEmpty else {
            exitMultiSelection()
            return
        }

        let remainingEntries = store.libraryOnDisplay.filter { entry in
            !interaction.selectedEntryIDs.contains(entry.tmdbID)
        }
        let scrollTarget = remainingEntries.first?.tmdbID

        for entry in entries {
            _ = store.deleteEntry(entry)
        }

        scrollState.scrolledID = scrollTarget
        exitMultiSelection()
    }

    private func enterMultiSelection() {
        updateSelectionDisplayItems()
        withAnimation(selectionModeAnimation) {
            interaction.enterMultiSelection()
        }
    }

    private func exitMultiSelection() {
        withAnimation(selectionModeAnimation) {
            interaction.exitMultiSelection()
        }
        selectionDisplayItems = nil
        selectionEntriesByID.removeAll(keepingCapacity: true)
    }

    private func refreshSelectionDisplayItemsIfNeeded() {
        guard interaction.isMultiSelecting else { return }
        updateSelectionDisplayItems()
    }

    private func updateSelectionDisplayItems() {
        let items = store.libraryDisplayItems
        let displayedIDs = Set(items.map(\.id))
        interaction.selectedEntryIDs.formIntersection(displayedIDs)
        selectionDisplayItems = items
        selectionEntriesByID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.entry) }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func filterToggle(for filter: LibraryStore.AnimeFilter) -> some View {
        Toggle(
            isOn: binding(for: filter),
            label: { Text(filter.name) }
        )
    }

    private func binding(for filter: LibraryStore.AnimeFilter) -> Binding<Bool> {
        .init(
            get: { store.filters.contains(filter) },
            set: {
                if $0 {
                    store.filters.insert(filter)
                } else {
                    store.filters.remove(filter)
                }
            }
        )
    }

    private func libraryViewPage<Content: View>(
        id: LibraryViewStyle,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(id)
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

        var detailMode: LibraryEntryDetailMode {
            switch self {
            case .gallery: .gallery
            case .list: .list
            case .grid: .grid
            }
        }

    }
}

fileprivate struct LibraryProfileLauncherBadge: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 6.5, weight: .bold))
                .background(.primary.opacity(0.30), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.4), lineWidth: 0.7)
                }
                .offset(x: 4, y: 4)
        }
    }
}

extension AnimeEntry.WatchStatus {
    fileprivate var batchActionSystemImage: String {
        switch self {
        case .planToWatch:
            "bookmark"
        case .watching:
            "play.circle"
        case .watched:
            "checkmark.circle"
        case .dropped:
            "xmark.circle"
        }
    }
}

fileprivate struct LibraryProfileSettingsBlendModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
            .compositingGroup()
    }
}

fileprivate struct LibraryViewTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blurRadius: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: yOffset)
            .blur(radius: blurRadius)
            .opacity(opacity)
            .compositingGroup()
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
