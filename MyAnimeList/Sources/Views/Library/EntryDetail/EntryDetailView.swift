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
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false
    @AppStorage(.broadcastScheduleEnabled) private var broadcastScheduleEnabled = true
    @AppStorage(.showProductionCompanyInsteadOfRuntime)
    private var showProductionCompanyInsteadOfRuntime = false

    @Bindable private var session: EntryDetailSession
    private let detailHost: LibraryEntryDetailHost
    private let onClose: ((LibraryEntrySyncIdentity) -> Void)?
    private let editingRequestID: UUID?
    private let onEditingRequestHandled: ((UUID) -> Void)?
    private let hostPresentationID: UUID?
    private let isCurrentHostPresentation: ((UUID) -> Bool)?

    @State private var conversionTask: Task<Void, Never>?
    @State private var conversionTaskID: UUID?

    private var currentLanguage: Language { followsSystemLanguage ? .current : preferredLanguage }
    private let scrollCoordinateSpaceName = "EntryDetailScroll"
    private let heroHeight: CGFloat = 420

    init(
        session: EntryDetailSession,
        detailHost: LibraryEntryDetailHost,
        onClose: ((LibraryEntrySyncIdentity) -> Void)? = nil,
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
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
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
            .id(session.instanceID)
            .transition(.opacity)
        }
        .animation(entryReplacementAnimation, value: session.instanceID)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarContent }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(
            session.entry.userInfoHasChanges(comparedTo: session.originalUserInfo)
        )
        .sheet(item: activeSheetBinding, onDismiss: session.activeSheetDidDismiss) { activeSheet in
            switch activeSheet {
            case .broadcastValidation:
                EntryDetailBroadcastValidationSheet(
                    model: session.broadcast,
                    searchTitle: broadcastTitleFallbackName,
                    displayTitle: session.model.displayTitle
                )
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
        .task(id: "\(session.instanceID)-\(currentLanguage.rawValue)") {
            await session.model.load(
                for: session.entry,
                language: currentLanguage
            )
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

    private var entryReplacementAnimation: Animation {
        .easeInOut(duration: 0.18)
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
            detailURL: session.model.primaryLinkURL ?? session.entry.linkToDetails,
            isFavorite: session.entry.favorite,
            showsConvertAction: session.entry.type != .movie,
            conversionInProgress: session.conversion.inProgress,
            convertMenuTitle: { convertMenuTitle },
            dropActionTitle: dropActionTitle,
            dropActionSystemImage: dropActionSystemImage,
            dropActionIsDestructive: session.entry.watchStatus != .dropped,
            broadcastPhase: session.broadcast.phase,
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

    // MARK: - Details Content

    @ViewBuilder
    private func detailsContent(_ proxy: ScrollViewProxy) -> some View {
        if !session.model.statCards.isEmpty {
            EntryDetailStatGrid(
                availableCards: session.model.statCards,
                productionCompanies: session.model.productionCompanies,
                entryType: session.entry.type,
                showProductionCompanyInsteadOfRuntime: showProductionCompanyInsteadOfRuntime,
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
                            seriesTMDbID: session.entry.tmdbID,
                            language: currentLanguage,
                            watchStatus: session.entry.watchStatus,
                            episodeProgressSummary: session.entry.episodeProgressSummary(
                                forSeason: season.seasonNumber
                            ),
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
                                isWatched: EntryDetailEpisodePresentation.isEpisodeWatched(
                                    episode.episodeNumber,
                                    inSeason: session.entry.type.seasonNumber ?? 0,
                                    watchStatus: session.entry.watchStatus,
                                    summary: session.entry.episodeProgressSummary(
                                        forSeason: session.entry.type.seasonNumber ?? 0
                                    )
                                )
                            )
                        }
                    }
                }
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
        ToolbarItem(placement: .topBarTrailing) {
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
    }

    private func saveAndDismissIfNeeded() {
        if hasUnsavedUserInfoChanges {
            saveUserEdits()
        }
        closePresentation()
    }

    private func requestWatchStatusChange(_ status: AnimeEntry.WatchStatus) {
        guard session.entry.watchStatus != status else { return }

        let creditsCompletion =
            status == .watched
            && (session.entry.type == .series || session.entry.type == .movie)

        withAnimation(.default) {
            _ = session.entry.updateWatchStatus(status)
        }
        updatePresentation {
            $0.dateUpdateSuggestion = session.entry.dateUpdateSuggestion(forTargetStatus: status)
        }
        if creditsCompletion {
            appReview.record(.entryWatched(entryID: session.entry.tmdbID), scheduleRequest: false)
            session.hasPendingWatchedReviewOpportunity = true
            if session.presentation.dateUpdateSuggestion == nil {
                schedulePendingWatchedReviewOpportunity()
            }
        }
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            session.isEditingDetails = false
        }
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
                language: currentLanguage
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
                language: currentLanguage
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
