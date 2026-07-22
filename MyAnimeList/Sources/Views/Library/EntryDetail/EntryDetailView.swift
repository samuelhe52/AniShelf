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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppReviewPromptController.self) private var appReview
    @Environment(\.libraryEntryDetailHost) private var detailHost
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false

    private let session: EntryDetailSession
    private let onClose: ((LibraryEntrySyncIdentity) -> Void)?
    private let editingRequestID: UUID?
    private let onEditingRequestHandled: ((UUID) -> Void)?
    private let hostPresentationID: UUID?
    private let isCurrentHostPresentation: ((UUID) -> Bool)?

    @State private var conversionTask: Task<Void, Never>?
    @State private var conversionTaskID: UUID?

    private var accentColor: Color { session.entry.favorite ? .orange : .blue }
    private var currentLanguage: Language { followsSystemLanguage ? .current : preferredLanguage }
    private let scrollCoordinateSpaceName = "EntryDetailScroll"
    private let heroHeight: CGFloat = 420

    init(
        session: EntryDetailSession,
        onClose: ((LibraryEntrySyncIdentity) -> Void)? = nil,
        editingRequestID: UUID? = nil,
        onEditingRequestHandled: ((UUID) -> Void)? = nil,
        hostPresentationID: UUID? = nil,
        isCurrentHostPresentation: ((UUID) -> Bool)? = nil
    ) {
        self.session = session
        self.onClose = onClose
        self.editingRequestID = editingRequestID
        self.onEditingRequestHandled = onEditingRequestHandled
        self.hostPresentationID = hostPresentationID
        self.isCurrentHostPresentation = isCurrentHostPresentation
    }

    var body: some View {
        @Bindable var bindableSession = session

        ZStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stretchyHeroSection(heroHeight: heroHeight)

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
                .scrollPosition($bindableSession.scrollPosition)
                .coordinateSpace(name: scrollCoordinateSpaceName)
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
        .presentationBackground(pageBackground)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(
            session.entry.userInfoHasChanges(comparedTo: session.originalUserInfo)
        )
        .sheet(item: activeSheetBinding, onDismiss: session.activeSheetDidDismiss) { activeSheet in
            switch activeSheet {
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
        .onChange(of: session.instanceID) {
            cancelConversionTask()
        }
        .onDisappear {
            cancelConversionTask()
        }
    }

    // MARK: - Hero

    private var pageBackground: Color {
        detailHost == .sheet ? Color(.systemGroupedBackground) : Color(.systemBackground)
    }

    private var entryReplacementAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var editingSectionRevealDelay: Duration {
        detailHost == .inspector ? .milliseconds(250) : .milliseconds(150)
    }

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

        if reduceMotion {
            proxy.scrollTo(
                EntryDetailScrollTarget.editingSection,
                anchor: .center
            )
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                proxy.scrollTo(
                    EntryDetailScrollTarget.editingSection,
                    anchor: .center
                )
            }
        }
        return true
    }

    private func stretchyHeroSection(heroHeight: CGFloat) -> some View {
        GeometryReader { proxy in
            let overscroll = max(proxy.frame(in: .named(scrollCoordinateSpaceName)).minY, 0)
            let stretchedHeight = heroHeight + overscroll

            heroSection(height: stretchedHeight)
                .offset(y: -overscroll)
        }
        .frame(height: heroHeight)
    }

    private func heroSection(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            heroArtwork

            // Top scrim — keeps toolbar buttons legible
            LinearGradient(
                colors: [.black.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.22)
            )

            // Gradient scrim for text legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: UnitPoint(x: 0.5, y: 0.35),
                endPoint: .bottom
            )

            // Fade bottom edge into page background
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, pageBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 6) {
                    if let logoImageURL = session.model.logoImageURL {
                        KFImageView(
                            url: logoImageURL,
                            targetSize: CGSize(width: 500, height: 500),
                            diskCacheExpiration: .longTerm
                        )
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .frame(height: 78)
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                    } else {
                        Text(session.model.displayTitle)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.78)
                            .multilineTextAlignment(.center)
                    }

                    if let subtitle = session.model.subtitleText {
                        Text(subtitle)
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if !session.model.metadataLineItems.isEmpty {
                        Text(session.model.metadataLineItems.joined(separator: "  ·  "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if !session.model.genreNames.isEmpty {
                        Text(session.model.genreNames.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .containerRelativeFrame(.horizontal)
        .frame(height: height)
        .clipped()
    }

    @ViewBuilder
    private var heroArtwork: some View {
        let url = session.model.heroImageURL ?? session.entry.backdropURL ?? session.entry.posterURL
        if let url {
            KFImageView(
                url: url,
                targetSize: CGSize(width: 1_200, height: 675),
                diskCacheExpiration: .longTerm
            )
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LinearGradient(
                colors: [accentColor.opacity(0.45), Color.blue.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
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
            onShare: { updatePresentation { $0.activeSheet = .sharing } },
            onToggleFavorite: toggleFavorite,
            onChangePoster: { updatePresentation { $0.activeSheet = .changePoster } },
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
            LazyVGrid(columns: statColumns, spacing: 12) {
                ForEach(session.model.statCards) { card in
                    if card.id == "episodes" {
                        Button {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                                proxy.scrollTo(
                                    EntryDetailScrollTarget.episodesSection,
                                    anchor: .top
                                )
                            }
                        } label: {
                            DetailStatCard(card: card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(
                                verbatim: "\(card.value), \(String(localized: card.title))"
                            )
                        )
                        .accessibilityHint(Text(EntryDetailL10n.jumpsToEpisodesSection))
                    } else {
                        DetailStatCard(card: card)
                    }
                }
            }
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
                isExpanded: characterExpandedBinding
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
                isExpanded: staffExpandedBinding
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
            isEditingDetails: editingDetailsBinding
        )
        .id(EntryDetailScrollTarget.editingSection)
    }

    private var statColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: min(max(session.model.statCards.count, 1), 3)
        )
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

    private var editingDetailsBinding: Binding<Bool> {
        Binding(
            get: { session.isEditingDetails },
            set: { session.isEditingDetails = $0 }
        )
    }

    private var characterExpandedBinding: Binding<Bool> {
        Binding(
            get: { session.isCharacterExpanded },
            set: { session.isCharacterExpanded = $0 }
        )
    }

    private var staffExpandedBinding: Binding<Bool> {
        Binding(
            get: { session.isStaffExpanded },
            set: { session.isStaffExpanded = $0 }
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

fileprivate struct EntryDetailPreviewHost: View {
    @State private var showDetail = false
    @State private var session: EntryDetailSession

    init() {
        let dataProvider = DataProvider.forPreview
        _session = State(
            initialValue: EntryDetailSession(
                entry: .yourName,
                repository: LibraryRepository(dataProvider: dataProvider)
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack {
                Button(String(localized: EntryDetailL10n.showDetail)) {
                    showDetail = true
                }
            }
            .sheet(isPresented: $showDetail) {
                NavigationStack {
                    EntryDetailView(
                        session: session
                    )
                }
            }
            .onAppear {
                showDetail = true
            }
        }
    }
}

#Preview {
    EntryDetailPreviewHost()
}
