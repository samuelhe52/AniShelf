//
//  EntryDetailView.swift
//  MyAnimeList
//
//  Created by Samuel He on 8/1/25.
//

import DataProvider
import Foundation
import LibrarySync
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppReviewPromptController.self) private var appReview
    @Environment(LibraryStore.self) private var store: LibraryStore?
    private let airingReminders = AiringReminderCoordinator.shared

    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.defaultPosterLanguage) private var posterLanguage: PosterLanguagePreference = .originalLanguage
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false
    @AppStorage(.broadcastScheduleEnabled) private var broadcastScheduleEnabled = true
    @AppStorage(.showProductionCompanyInsteadOfRuntime)
    private var showProductionCompanyInsteadOfRuntime = false
    #if os(macOS)
        @AppStorage(.macEntryDetailHeaderStyle) private var macHeaderStyle: MacEntryDetailHeaderStyle = .compact
        @Environment(\.macInspectorPosterFlight) private var posterFlight
    #endif

    @Bindable private var session: EntryDetailSession
    private let detailHost: LibraryEntryDetailHost
    private let onClose: ((LibraryEntryIdentity) -> Void)?
    private let editingRequestID: UUID?
    private let onEditingRequestHandled: ((UUID) -> Void)?
    private let hostPresentationID: UUID?
    private let isCurrentHostPresentation: ((UUID) -> Bool)?

    @State private var conversionTask: Task<Void, Never>?
    @State private var conversionTaskID: UUID?

    private var currentLanguage: Language { followsSystemLanguage ? .current : preferredLanguage }
    /// The hero shows the title logo and centers the quick actions below it.
    private var showsHero: Bool {
        #if os(macOS)
            macHeaderStyle == .cinematic
        #else
            true
        #endif
    }
    private var hasEpisodesSection: Bool {
        switch session.entry.type {
        case .series: !session.model.seasonCards.isEmpty
        case .season: !session.model.episodeCards.isEmpty
        case .movie: false
        }
    }
    private let scrollCoordinateSpaceName = "EntryDetailScroll"
    #if os(macOS)
        // About 52 points sit under the window toolbar.
        private let heroHeight: CGFloat = 412
    #else
        private let heroHeight: CGFloat = 420
    #endif

    init(
        session: EntryDetailSession,
        detailHost: LibraryEntryDetailHost,
        onClose: ((LibraryEntryIdentity) -> Void)? = nil,
        editingRequestID: UUID? = nil,
        onEditingRequestHandled: ((UUID) -> Void)? = nil,
        hostPresentationID: UUID? = nil,
        isCurrentHostPresentation: ((UUID) -> Bool)? = nil
    ) {
        self.session = session
        self.detailHost = detailHost
        self.onClose = onClose
        self.editingRequestID = editingRequestID
        self.onEditingRequestHandled = onEditingRequestHandled
        self.hostPresentationID = hostPresentationID
        self.isCurrentHostPresentation = isCurrentHostPresentation
    }

    var body: some View {
        pageWithPrompts
            .environment(session)
            .task(id: "\(session.instanceID)-\(currentLanguage.rawValue)-\(showsHero)") {
                await session.model.load(
                    for: session.entry,
                    language: currentLanguage,
                    includesTitleLogo: showsHero
                )
                await session.refreshEpisodeCountsIfEligible(language: currentLanguage)
                await store?.restoreMissingParentSeries(for: session.entry)
            }
            .onChange(of: session.entry.supportsEpisodeNotes) { hadOwner, hasOwner in
                // Without an owner the snapshot read no episode notes, and note editing was
                // unavailable. Adopt the restored parent's notes so Discard keeps them.
                guard !hadOwner, hasOwner else { return }
                session.originalUserInfo.episodeNotes = session.entry.episodeNotes
            }
            .task(id: broadcastActivationTaskID) {
                session.broadcast.update(broadcastActivationTaskID.activation)
            }
            .onChange(of: session.instanceID) {
                cancelConversionTask()
            }
            .onDisappear {
                cancelConversionTask()
            }
    }

    /// The scrolling page and its chrome.
    private var page: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    #if os(macOS)
                        macInspectorContent(proxy)
                    #else
                        iOSPageContent(proxy)
                    #endif
                }
                .supportedSwipeActionsContainer()
                .scrollPosition($session.scrollPosition)
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .preferredNavigationBarScrollEdgeEffect()
                .task(id: editingRequestID) {
                    let requestID = editingRequestID
                    guard let requestID else { return }
                    guard await revealEditingSection(using: proxy) else { return }
                    onEditingRequestHandled?(requestID)
                }
            }
            // A fetched detail fills in place; switching entries is not animated here.
            .animation(fetchedDetailAnimation, value: session.model.fetchedDetailRevision)
            .id(session.instanceID)
            .transition(.opacity)
        }
        .animation(entryReplacementAnimation, value: session.instanceID)
        .heroIgnoresTopSafeArea(showsHero)
        .hiddenNavigationBarBackground()
        #if !os(macOS)
            // On the Mac the inspector's root view owns Hide Inspector.
            .toolbar { toolbarContent }
        #endif
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(
            session.entry.userInfoHasChanges(comparedTo: session.originalUserInfo)
        )
    }

    /// The page with its sheets and the season conversion dialogs.
    private var pageWithSheets: some View {
        page
            .sheet(item: activeSheetBinding, onDismiss: session.activeSheetDidDismiss) { activeSheet in
                activeSheetContent(activeSheet)
            }
            .confirmationDialog(
                EntryDetailL10n.convertToWhichSeason,
                isPresented: showSeasonPickerBinding,
                titleVisibility: .visible
            ) {
                if session.conversion.isFetchingSeasons {
                    ProgressView()
                } else if session.conversion.seasonNumberOptions.isEmpty {
                    Button(EntryDetailL10n.noSeasonsAvailable, role: .cancel) {}
                } else {
                    ForEach(session.conversion.seasonNumberOptions, id: \.self) { seasonNumber in
                        Button("Season \(seasonNumber)") {
                            startConversionTask {
                                await convertSeriesToSeason(seasonNumber: seasonNumber)
                            }
                        }
                    }
                }
                Button(EntryDetailL10n.cancel, role: .cancel) {}
            }
            .alert(
                EntryDetailL10n.siblingSeasonExists,
                isPresented: showSiblingSeasonWarningBinding
            ) {
                Button(EntryDetailL10n.convertAnyway, role: .destructive) {
                    startConversionTask {
                        await convertSeasonToSeries()
                    }
                }
                Button(EntryDetailL10n.cancel, role: .cancel) {}
            } message: {
                Text(EntryDetailL10n.siblingSeasonExistsMessage)
            }
    }

    /// The page with the tracking prompts that follow status and progress changes.
    private var pageWithPrompts: some View {
        pageWithSheets
            .alert(
                EntryDetailL10n.markAsWatchedPromptTitle,
                isPresented: isEpisodeProgressCompletionPromptPresented,
                presenting: session.presentation.episodeProgressCompletionPrompt
            ) { _ in
                Button(EntryDetailL10n.markAsWatched) {
                    updatePresentation { $0.episodeProgressCompletionPrompt = nil }
                    requestWatchStatusChange(.watched)
                }
                Button(EntryDetailL10n.notNow, role: .cancel) {
                    updatePresentation { $0.episodeProgressCompletionPrompt = nil }
                }
            } message: { prompt in
                Text(episodeProgressCompletionPromptMessage(for: prompt))
            }
            .alert(
                EntryDetailL10n.updateDatesPromptTitle,
                isPresented: isDateUpdateSuggestionPresented,
                presenting: session.presentation.dateUpdateSuggestion
            ) { suggestion in
                Button(EntryDetailL10n.dateSuggestionActionTitle(for: suggestion)) {
                    updatePresentation { $0.dateUpdateSuggestion = nil }
                    withAnimation(.default) {
                        session.entry.applyDateUpdateSuggestion(suggestion)
                    }
                    schedulePendingWatchedReviewOpportunity()
                }
                Button(EntryDetailL10n.later, role: .cancel) {
                    updatePresentation { $0.dateUpdateSuggestion = nil }
                    schedulePendingWatchedReviewOpportunity()
                }
            } message: { suggestion in
                Text(EntryDetailL10n.dateSuggestionMessage(for: suggestion))
            }
            .alert(
                EntryDetailL10n.rewatchPromptTitle,
                isPresented: showRewatchPromptBinding
            ) {
                Button(EntryDetailL10n.startRewatch) {
                    resolveRewatchPrompt(isRewatching: true)
                }
                Button(EntryDetailL10n.notARewatch, role: .cancel) {
                    resolveRewatchPrompt(isRewatching: false)
                }
            } message: {
                Text(rewatchPromptMessage)
            }
    }

    private var broadcastActivation: EntryDetailBroadcastModel.Activation {
        EntryDetailBroadcastModel.Activation(
            isEnabled: broadcastScheduleEnabled,
            entryType: session.entry.type,
            seriesStatus: session.entry.detail?.status
        )
    }

    private var broadcastActivationTaskID: BroadcastActivationTaskID {
        BroadcastActivationTaskID(
            sessionInstanceID: session.instanceID,
            activation: broadcastActivation
        )
    }

    private struct BroadcastActivationTaskID: Equatable {
        let sessionInstanceID: UUID
        let activation: EntryDetailBroadcastModel.Activation
    }

    // MARK: - Hero

    /// The iPad inspector cross-fades to another entry.
    ///
    /// The Mac inspector swaps instantly, as Mail and Finder do; a fade there also draws its
    /// material cards flat dark.
    private var entryReplacementAnimation: Animation? {
        #if os(macOS)
            nil
        #else
            .easeInOut(duration: 0.18)
        #endif
    }

    private var fetchedDetailAnimation: Animation {
        .smooth(duration: 0.25)
    }

    private let editingSectionRevealDelay: Duration = .milliseconds(150)

    @discardableResult
    @MainActor
    private func revealEditingSection(using proxy: ScrollViewProxy) async -> Bool {
        session.isEditingDetails = true
        do {
            try await Task.sleep(for: editingSectionRevealDelay)
        } catch {
            return false
        }
        guard !Task.isCancelled else { return false }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
            proxy.scrollTo(
                EntryDetailScrollTarget.editingSection,
                anchor: .center
            )
        }
        return true
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        EntryDetailQuickActionsRow(
            entry: session.entry,
            openInLinks: EntryOpenInLinks(
                entry: session.entry,
                homepageURL: session.model.primaryLinkURL ?? session.entry.linkToDetails
            ),
            isFavorite: session.entry.favorite,
            isCentered: showsHero,
            showsConvertAction: session.entry.type != .movie,
            conversionInProgress: session.conversion.inProgress,
            convertMenuTitle: { convertMenuTitle },
            dropActionTitle: dropActionTitle,
            dropActionSystemImage: dropActionSystemImage,
            dropActionIsDestructive: session.entry.watchStatus != .dropped,
            broadcastPhase: session.broadcast.phase,
            airingReminderContext: EntryDetailAiringReminderContext(
                entryIdentity: session.entryIdentity,
                displayTitle: session.model.displayTitle,
                seasonNumber: session.entry.type.seasonNumber,
                resolvedShow: session.broadcast.resolvedShow
            ),
            hasAiringReminder: airingReminders.snapshot.subscription(
                for: session.entryIdentity.rawID
            ) != nil,
            onShare: { updatePresentation { $0.activeSheet = .sharing } },
            onToggleFavorite: toggleFavorite,
            onChangePoster: { updatePresentation { $0.activeSheet = .changePoster } },
            onPresentBroadcastValidation: presentBroadcastValidation,
            onRetryBroadcast: session.broadcast.retryAutomaticResolution,
            onConvert: {
                startConversionTask {
                    await handleConvertTap()
                }
            },
            onToggleDroppedStatus: toggleDroppedStatus
        )
    }

    // MARK: - Sheets

    @ViewBuilder
    private func activeSheetContent(_ activeSheet: EntryDetailSheet) -> some View {
        switch activeSheet {
        case .broadcastValidation:
            EntryDetailBroadcastValidationSheet(
                model: session.broadcast,
                searchTitle: broadcastTitleFallbackName,
                displayTitle: session.model.displayTitle
            )
            .presentationBackground(Color.platformSystemGroupedBackground)
            .macSheetFrame(width: 600, height: 620)
        case .changePoster:
            NavigationStack {
                PosterSelectionView(
                    tmdbID: session.entry.tmdbID,
                    type: session.entry.type,
                    originalPosterLanguageCode: session.entry.originalLanguageCode
                        ?? session.entry.parentSeriesEntry?.originalLanguageCode
                ) { url in
                    if url != session.entry.posterURL || !session.entry.usingCustomPoster {
                        session.entry.updateCustomPosterURL(url)
                    }
                }
                .navigationTitle(EntryDetailL10n.changePoster)
            }
        case .sharing:
            AnimeSharingSheet(entry: session.entry)
        }
    }

    // MARK: - Shared Hero

    private var heroSection: some View {
        EntryDetailHeroSection(
            imageURL: session.model.heroImageURL
                ?? session.entry.backdropURL
                ?? session.entry.posterURL,
            logoImageURL: session.model.logoImageURL,
            displayTitle: session.model.displayTitle,
            subtitleText: session.model.subtitleText,
            metadataLineItems: session.model.metadataLineItems,
            genreNames: session.model.genreNames,
            accentColor: session.entry.favorite ? .orange : .blue,
            pageBackground: detailHost.pageBackground,
            scrollCoordinateSpaceName: scrollCoordinateSpaceName,
            height: heroHeight
        )
    }

    // MARK: - iOS Page

    #if !os(macOS)
        /// The iOS page: a hero with the title and quick actions, then the detail cards.
        private func iOSPageContent(_ proxy: ScrollViewProxy) -> some View {
            VStack(spacing: 0) {
                heroSection

                VStack(alignment: .leading, spacing: 20) {
                    quickActionsRow
                        .padding(.top, -20)
                        .padding(.bottom, 4)
                    detailsContent(proxy)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: 1_000)
                .frame(maxWidth: .infinity)
            }
        }
    #endif

    // MARK: - Mac Inspector

    #if os(macOS)
        /// Either header sits above the same native Mac controls and grouped cards.
        private func macInspectorContent(_ proxy: ScrollViewProxy) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                switch macHeaderStyle {
                case .compact:
                    MacEntryDetailHeader(
                        posterURL: session.entry.posterURL,
                        displayTitle: session.model.displayTitle,
                        subtitleText: session.model.subtitleText,
                        metadataLineItems: session.model.metadataLineItems,
                        genreNames: session.model.genreNames
                    ) {
                        quickActionsRow
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                case .cinematic:
                    heroSection
                        .onAppear {
                            // No poster is visible in this mode; a batch must not fly one
                            // from the compact header's last recorded position.
                            posterFlight?.sourceFrame = nil
                        }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if macHeaderStyle == .cinematic {
                        // Overlaps the hero's fade, as on iOS.
                        quickActionsRow
                            .padding(.top, -20)
                            .padding(.bottom, 4)
                    }
                    detailsContent(proxy)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .environment(\.popupPanelStyle, .grouped)
        }
    #endif

    // MARK: - Details Content

    @ViewBuilder
    private func detailsContent(_ proxy: ScrollViewProxy) -> some View {
        if !session.model.statCards.isEmpty {
            EntryDetailStatGrid(
                availableCards: session.model.statCards,
                productionCompanies: session.model.productionCompanies,
                entryType: session.entry.type,
                showProductionCompanyInsteadOfRuntime: showProductionCompanyInsteadOfRuntime,
                canJumpToEpisodes: hasEpisodesSection,
                onJumpToEpisodes: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                        proxy.scrollTo(EntryDetailScrollTarget.episodesSection, anchor: .top)
                    }
                }
            )
        }

        editingSection

        sectionCard(EntryDetailL10n.overview, systemImage: "text.alignleft") {
            Text(session.model.overviewText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !session.model.characterCards.isEmpty {
            PopupDisclosureCard(
                session.model.characterSectionTitle,
                systemImage: "person.2.fill",
                isExpanded: $session.isCharacterExpanded
            ) {
                horizontalCards(session.model.characterCards) { card in
                    PersonCardView(card: card)
                }
            }
        }

        if !session.model.staffCards.isEmpty {
            PopupDisclosureCard(
                EntryDetailL10n.staff,
                systemImage: "person.2.fill",
                isExpanded: $session.isStaffExpanded
            ) {
                horizontalCards(session.model.staffCards) { card in
                    PersonCardView(card: card)
                }
            }
        }

        switch session.entry.type {
        case .series:
            if !session.model.seasonCards.isEmpty {
                LazyVStack(spacing: 18) {
                    ForEach(session.model.seasonCards) { season in
                        SeriesSeasonEpisodeGroupView(
                            season: season,
                            entry: session.entry,
                            seriesTMDbID: session.entry.tmdbID,
                            language: currentLanguage,
                            watchStatus: session.entry.watchStatus,
                            episodeProgressSummary: episodeProgressTrackingEnabled
                                ? session.entry.episodeProgressSummary(
                                    forSeason: season.seasonNumber
                                ) : nil,
                            collapseByDefault: session.model.collapseSeriesSeasonsByDefault,
                            sectionTitle: season.id == session.model.seasonCards.first?.id
                                ? EntryDetailL10n.episodes
                                : nil,
                            sectionSystemImage: season.id == session.model.seasonCards.first?.id
                                ? "play.rectangle.on.rectangle.fill"
                                : nil
                        )
                        .id("\(season.id)-\(session.model.collapseSeriesSeasonsByDefault)")
                    }
                }
                .id(EntryDetailScrollTarget.episodesSection)
            }
        case .season:
            if !session.model.episodeCards.isEmpty {
                sectionCard(EntryDetailL10n.episodes, systemImage: "play.rectangle.on.rectangle.fill") {
                    LazyVStack(spacing: 10) {
                        ForEach(session.model.episodeCards) { episode in
                            EpisodeRowView(
                                card: episode,
                                previewContext: .init(
                                    seriesTMDbID: session.entry.type.parentSeriesID
                                        ?? session.entry.tmdbID,
                                    seasonNumber: session.entry.type.seasonNumber ?? 0,
                                    language: currentLanguage
                                ),
                                isWatched: episodeProgressTrackingEnabled
                                    && EntryDetailEpisodePresentation.isEpisodeWatched(
                                        episode.episodeNumber,
                                        inSeason: session.entry.type.seasonNumber ?? 0,
                                        watchStatus: session.entry.watchStatus,
                                        summary: session.entry.episodeProgressSummary(
                                            forSeason: session.entry.type.seasonNumber ?? 0
                                        )
                                    ),
                                entry: session.entry
                            )
                        }
                    }
                }
                #if os(macOS)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                #else
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                #endif
                .id(EntryDetailScrollTarget.episodesSection)
            }
        case .movie:
            EmptyView()
        }

        if let errorMessage = session.model.loadError {
            sectionCard(EntryDetailL10n.tmdb) {
                ContentUnavailableView(
                    String(localized: EntryDetailL10n.couldNotLoadDetails),
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var editingSection: some View {
        EntryDetailTrackingSection(
            entry: session.entry,
            originalNotes: session.originalUserInfo.notes,
            originalEpisodeNotes: session.originalUserInfo.episodeNotes,
            scoringEnabled: scoringEnabled,
            episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
            onWatchStatusSelected: requestWatchStatusChange,
            onEpisodeProgressCompletionSuggested: handleEpisodeProgressCompletionSuggestion,
            isEditingDetails: $session.isEditingDetails
        )
        .id(EntryDetailScrollTarget.editingSection)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        _ title: LocalizedStringResource,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        PopupSectionCard(title, systemImage: systemImage) {
            content()
        }
    }

    @ViewBuilder
    private func horizontalCards<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Identifiable {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(data) { element in
                    content(element)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .platformTrailing) {
            doneToolbarControl
        }
    }

    // MARK: - Actions

    private func toggleFavorite() {
        session.toggleFavorite()
    }

    private func toggleDroppedStatus() {
        requestWatchStatusChange(session.entry.watchStatus == .dropped ? .watching : .dropped)
    }

    private func presentBroadcastValidation() {
        updatePresentation { $0.activeSheet = .broadcastValidation }
        session.broadcast.startTitleFallback(named: broadcastTitleFallbackName)
    }

    private var broadcastTitleFallbackName: String {
        let seriesEntry = session.entry.parentSeriesEntry ?? session.entry
        let englishTitle = seriesEntry.nameTranslations
            .sorted { $0.key < $1.key }
            .first { key, value in
                key.lowercased().hasPrefix("en-")
                    && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }?
            .value
        return englishTitle ?? seriesEntry.name
    }

    private var dropActionTitle: LocalizedStringResource {
        session.entry.watchStatus == .dropped
            ? EntryDetailL10n.undrop : EntryDetailL10n.markAsDropped
    }

    private var dropActionSystemImage: String {
        session.entry.watchStatus == .dropped ? "arrow.uturn.backward.circle" : "xmark.circle"
    }

    @ViewBuilder
    private var doneToolbarControl: some View {
        if !shouldConfirmBeforeSaving {
            Button(String(localized: EntryDetailL10n.done)) {
                closePresentation()
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
        } else {
            Menu {
                Button(EntryDetailL10n.save) {
                    saveAndDismissIfNeeded()
                }
                Button(EntryDetailL10n.discardChanges, role: .destructive) {
                    discardUserEdits()
                    closePresentation()
                }
            } label: {
                Text(String(localized: EntryDetailL10n.done))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var hasUnsavedUserInfoChanges: Bool {
        session.entry.userInfoHasChanges(comparedTo: session.originalUserInfo)
    }

    private var isEpisodeProgressCompletionPromptPresented: Binding<Bool> {
        Binding(
            get: { session.presentation.episodeProgressCompletionPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    updatePresentation { presentation in
                        presentation.episodeProgressCompletionPrompt = nil
                    }
                }
            }
        )
    }

    private var showRewatchPromptBinding: Binding<Bool> {
        Binding(
            get: { session.presentation.showRewatchPrompt },
            set: { isPresented in
                if !isPresented {
                    updatePresentation { presentation in
                        presentation.showRewatchPrompt = false
                    }
                }
            }
        )
    }

    private var isDateUpdateSuggestionPresented: Binding<Bool> {
        Binding(
            get: { session.presentation.dateUpdateSuggestion != nil },
            set: { isPresented in
                if !isPresented {
                    updatePresentation { presentation in
                        presentation.dateUpdateSuggestion = nil
                    }
                }
            }
        )
    }

    private var activeSheetBinding: Binding<EntryDetailSheet?> {
        Binding(
            get: { session.presentation.activeSheet },
            set: { activeSheet in
                updatePresentation { presentation in
                    presentation.activeSheet = activeSheet
                }
            }
        )
    }

    private var showSeasonPickerBinding: Binding<Bool> {
        Binding(
            get: { session.presentation.showSeasonPicker },
            set: { isPresented in
                updatePresentation { presentation in
                    presentation.showSeasonPicker = isPresented
                }
            }
        )
    }

    private var showSiblingSeasonWarningBinding: Binding<Bool> {
        Binding(
            get: { session.presentation.showSiblingSeasonWarning },
            set: { isPresented in
                updatePresentation { presentation in
                    presentation.showSiblingSeasonWarning = isPresented
                }
            }
        )
    }

    private func updatePresentation(
        _ update: (inout EntryDetailPresentationState) -> Void
    ) {
        session.updatePresentation(
            from: hostPresentationID,
            ifCurrent: isCurrentHostPresentation,
            update
        )
    }

    private var shouldConfirmBeforeSaving: Bool {
        // Only non-incremental note changes require confirmation.
        !session.entry.notes.hasPrefix(session.originalUserInfo.notes)
            || session.originalUserInfo.episodeNotes.contains { note in
                !note.isEmpty && !(session.entry.episodeNote(at: note.anchor)?.text ?? "").hasPrefix(note.text)
            }
    }

    private func saveAndDismissIfNeeded() {
        if hasUnsavedUserInfoChanges {
            saveUserEdits()
        }
        closePresentation()
    }

    private func requestWatchStatusChange(_ status: AnimeEntry.WatchStatus) {
        guard session.entry.watchStatus != status else { return }

        let mayBeRewatch = session.entry.watchStatus == .watched && status == .watching
        let creditsCompletion =
            status == .watched
            && (session.entry.type == .series || session.entry.type == .movie)

        withAnimation(.default) {
            _ = session.entry.updateWatchStatus(status)
        }
        if mayBeRewatch {
            // The date suggestion follows once the user answers the rewatch prompt.
            updatePresentation { $0.showRewatchPrompt = true }
            return
        }
        updatePresentation {
            $0.dateUpdateSuggestion = session.entry.dateUpdateSuggestion(forTargetStatus: status)
        }
        if creditsCompletion {
            appReview.record(.entryWatched(entryID: session.entry.libraryIdentity), scheduleRequest: false)
            session.hasPendingWatchedReviewOpportunity = true
            if session.presentation.dateUpdateSuggestion == nil {
                schedulePendingWatchedReviewOpportunity()
            }
        }
    }

    private func resolveRewatchPrompt(isRewatching: Bool) {
        if isRewatching {
            withAnimation(.default) {
                _ = session.entry.startRewatch()
            }
        }
        updatePresentation {
            $0.showRewatchPrompt = false
            $0.dateUpdateSuggestion = session.entry.dateUpdateSuggestion(forTargetStatus: .watching)
        }
    }

    private var rewatchPromptMessage: LocalizedStringResource {
        session.entry.type == .movie
            ? EntryDetailL10n.rewatchPromptMovieMessage
            : EntryDetailL10n.rewatchPromptEpisodeMessage
    }

    private func schedulePendingWatchedReviewOpportunity() {
        guard session.hasPendingWatchedReviewOpportunity else { return }
        session.hasPendingWatchedReviewOpportunity = false
        appReview.scheduleRequestIfEligible()
    }

    private func handleEpisodeProgressCompletionSuggestion(
        _ prompt: AnimeEntryEpisodeProgressCompletionPrompt
    ) {
        updatePresentation { $0.episodeProgressCompletionPrompt = prompt }
    }

    private func episodeProgressCompletionPromptMessage(
        for prompt: AnimeEntryEpisodeProgressCompletionPrompt
    ) -> LocalizedStringResource {
        switch prompt {
        case .seasonWatched:
            EntryDetailL10n.seasonEpisodeProgressFinishedMessage
        case .seriesWatched:
            EntryDetailL10n.seriesEpisodeProgressFinishedMessage
        }
    }

    private var convertMenuTitle: LocalizedStringResource {
        switch session.entry.type {
        case .series:
            EntryDetailL10n.convertToSeason
        case .season:
            EntryDetailL10n.convertToSeries
        case .movie:
            preconditionFailure("Movies do not expose conversion actions.")
        }
    }

    private func saveUserEdits() {
        do {
            try session.save()
            session.originalUserInfo = session.entry.userInfo
            session.originalTrackingUpdatedAt = session.entry.trackingUpdatedAt
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    private func discardUserEdits() {
        session.entry.updateUserInfo(from: session.originalUserInfo)
        session.entry.trackingUpdatedAt = session.originalTrackingUpdatedAt
        do {
            try session.save()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        #if !os(macOS)
            // The Mac inspector keeps Tracking open; it is the inspector's main content.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                session.isEditingDetails = false
            }
        #endif
    }

    private func handleConvertTap() async {
        guard !session.conversion.inProgress else { return }
        switch session.entry.type {
        case .series:
            await presentSeasonPicker()
        case .season:
            if hasSiblingSeasonEntry {
                updatePresentation { $0.showSiblingSeasonWarning = true }
            } else {
                await convertSeasonToSeries()
            }
        case .movie:
            return
        }
    }

    private var hasSiblingSeasonEntry: Bool {
        session.model.hasSiblingSeasonEntry(for: session.entry)
    }

    private func presentSeasonPicker() async {
        session.conversion.isFetchingSeasons = true
        session.conversion.inProgress = true
        defer {
            session.conversion.isFetchingSeasons = false
            session.conversion.inProgress = false
        }
        do {
            session.conversion.seasonNumberOptions = try await session.model.seasonNumberOptions(
                for: session.entry,
                language: currentLanguage
            )
            guard !Task.isCancelled else { return }
            updatePresentation { $0.showSeasonPicker = true }
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    private func convertSeasonToSeries() async {
        guard case .season(_, _) = session.entry.type else { return }
        session.conversion.inProgress = true
        defer { session.conversion.inProgress = false }
        do {
            try await session.model.convertSeasonToSeries(
                session.entry,
                language: currentLanguage,
                posterLanguage: posterLanguage
            )
            guard !Task.isCancelled else { return }
            ToastCenter.global.completionState = .completed(EntryDetailL10n.convertedToSeries)
            closePresentation()
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    private func convertSeriesToSeason(seasonNumber: Int) async {
        session.conversion.inProgress = true
        defer { session.conversion.inProgress = false }
        do {
            try await session.model.convertSeriesToSeason(
                session.entry,
                seasonNumber: seasonNumber,
                language: currentLanguage,
                posterLanguage: posterLanguage
            )
            guard !Task.isCancelled else { return }
            ToastCenter.global.completionState = .completed(EntryDetailL10n.convertedToSeason)
            closePresentation()
        } catch {
            guard !Task.isCancelled, !Self.isCancellation(error) else { return }
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    private func startConversionTask(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        guard conversionTask == nil else { return }

        let taskID = UUID()
        conversionTaskID = taskID
        conversionTask = Task { @MainActor in
            await operation()
            guard conversionTaskID == taskID else { return }
            conversionTask = nil
            conversionTaskID = nil
        }
    }

    private func cancelConversionTask() {
        conversionTask?.cancel()
        conversionTask = nil
        conversionTaskID = nil
    }

    private func closePresentation() {
        if let onClose {
            onClose(session.entryIdentity)
        } else {
            dismiss()
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
