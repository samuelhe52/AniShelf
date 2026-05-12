//
//  EntryDetailView.swift
//  MyAnimeList
//
//  Created by Samuel He on 8/1/25.
//

import DataProvider
import SwiftData
import SwiftUI

struct EntryDetailView: View {
    @Environment(\.dataHandler) private var dataHandler
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true

    let entry: AnimeEntry
    private let startInEditingMode: Bool

    @State private var model: EntryDetailViewModel
    @State private var presentation = EntryDetailPresentationState()
    @State private var isEditingDetails: Bool
    @State private var originalUserInfo: UserEntryInfo
    @State private var conversion = EntryDetailConversionState()
    @State private var didAutoScrollToEditingSection = false
    @State private var isCharacterExpanded = true
    @State private var isStaffExpanded = false

    private var accentColor: Color { entry.favorite ? .orange : .blue }
    private var currentLanguage: Language { followsSystemLanguage ? .current : preferredLanguage }
    private let heroHeight: CGFloat = 420
    private let scrollCoordinateSpaceName = "EntryDetailScroll"

    init(
        entry: AnimeEntry,
        repository: LibraryRepository,
        startInEditingMode: Bool = false
    ) {
        self.entry = entry
        self.startInEditingMode = startInEditingMode
        self._model = State(initialValue: EntryDetailViewModel(repository: repository))
        self._isEditingDetails = State(initialValue: startInEditingMode)
        self._originalUserInfo = State(initialValue: entry.userInfo)
        self._isCharacterExpanded = State(
            initialValue: Self.defaultExpansionState(
                forKey: .entryDetailCharactersExpandedByDefault,
                defaultValue: true
            )
        )
        self._isStaffExpanded = State(
            initialValue: Self.defaultExpansionState(
                forKey: .entryDetailStaffExpandedByDefault,
                defaultValue: false
            )
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    stretchyHeroSection

                    VStack(alignment: .leading, spacing: 20) {
                        quickActionsRow
                            .padding(.top, -20)
                            .padding(.bottom, 4)
                        detailsContent(proxy)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .onAppear {
                guard startInEditingMode, !didAutoScrollToEditingSection else { return }
                didAutoScrollToEditingSection = true
                isEditingDetails = true
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    await MainActor.run {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                            proxy.scrollTo(EntryDetailScrollTarget.editingSection, anchor: .center)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarContent }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(entry.userInfoHasChanges(comparedTo: originalUserInfo))
        .sheet(item: $presentation.activeSheet) { activeSheet in
            switch activeSheet {
            case .changePoster:
                NavigationStack {
                    PosterSelectionView(
                        tmdbID: entry.tmdbID,
                        type: entry.type,
                        originalPosterLanguageCode: entry.originalLanguageCode
                            ?? entry.parentSeriesEntry?.originalLanguageCode
                    ) { url in
                        if url != entry.posterURL {
                            entry.usingCustomPoster = true
                        }
                        entry.posterURL = url
                    }
                    .navigationTitle(EntryDetailL10n.changePoster)
                }
            case .sharing:
                AnimeSharingSheet(entry: entry)
            }
        }
        .confirmationDialog(
            EntryDetailL10n.convertToWhichSeason,
            isPresented: $presentation.showSeasonPicker,
            titleVisibility: .visible
        ) {
            if conversion.isFetchingSeasons {
                ProgressView()
            } else if conversion.seasonNumberOptions.isEmpty {
                Button(EntryDetailL10n.noSeasonsAvailable, role: .cancel) {}
            } else {
                ForEach(conversion.seasonNumberOptions, id: \.self) { seasonNumber in
                    Button("Season \(seasonNumber)") {
                        Task { await convertSeriesToSeason(seasonNumber: seasonNumber) }
                    }
                }
            }
            Button(EntryDetailL10n.cancel, role: .cancel) {}
        }
        .alert(EntryDetailL10n.siblingSeasonExists, isPresented: $presentation.showSiblingSeasonWarning) {
            Button(EntryDetailL10n.convertAnyway, role: .destructive) {
                Task { await convertSeasonToSeries() }
            }
            Button(EntryDetailL10n.cancel, role: .cancel) {}
        } message: {
            Text(EntryDetailL10n.siblingSeasonExistsMessage)
        }
        .task(id: "\(entry.tmdbID)-\(currentLanguage.rawValue)") {
            await model.load(for: entry, language: currentLanguage, dataHandler: dataHandler)
        }
    }

    // MARK: - Hero

    private var stretchyHeroSection: some View {
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
                    colors: [.clear, Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 6) {
                    if let logoImageURL = model.logoImageURL {
                        KFImageView(url: logoImageURL, targetWidth: 800, diskCacheExpiration: .longTerm)
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .frame(height: 78)
                            .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                    } else {
                        Text(model.displayTitle)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.78)
                            .multilineTextAlignment(.center)
                    }

                    if let subtitle = model.subtitleText {
                        Text(subtitle)
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if !model.metadataLineItems.isEmpty {
                        Text(model.metadataLineItems.joined(separator: "  ·  "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }

                    if !model.genreNames.isEmpty {
                        Text(model.genreNames.joined(separator: ", "))
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
        let url = model.heroImageURL ?? entry.backdropURL ?? entry.posterURL
        if let url {
            KFImageView(url: url, targetWidth: 1_200, diskCacheExpiration: .longTerm)
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
            detailURL: model.primaryLinkURL ?? entry.linkToDetails,
            isFavorite: entry.favorite,
            showsConvertAction: entry.type != .movie,
            conversionInProgress: conversion.inProgress,
            convertMenuTitle: { convertMenuTitle },
            dropActionTitle: dropActionTitle,
            dropActionSystemImage: dropActionSystemImage,
            dropActionIsDestructive: entry.watchStatus != .dropped,
            onShare: { presentation.activeSheet = .sharing },
            onToggleFavorite: toggleFavorite,
            onChangePoster: { presentation.activeSheet = .changePoster },
            onConvert: handleConvertTap,
            onToggleDroppedStatus: toggleDroppedStatus
        )
    }

    // MARK: - Details Content

    @ViewBuilder
    private func detailsContent(_ proxy: ScrollViewProxy) -> some View {
        if !model.statCards.isEmpty {
            LazyVGrid(columns: statColumns, spacing: 12) {
                ForEach(model.statCards) { card in
                    DetailStatCard(card: card)
                        .onTapGesture {
                            if card.id == "episodes" {
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                                    proxy.scrollTo(
                                        EntryDetailScrollTarget.episodesSection,
                                        anchor: .top
                                    )
                                }
                            }
                        }
                }
            }
        }

        editingSection

        sectionCard(EntryDetailL10n.overview, systemImage: "text.alignleft") {
            Text(model.overviewText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !model.characterCards.isEmpty {
            PopupDisclosureCard(
                model.characterSectionTitle,
                systemImage: "person.2.fill",
                isExpanded: $isCharacterExpanded
            ) {
                horizontalCards(model.characterCards) { card in
                    PersonCardView(card: card)
                }
            }
        }

        if !model.staffCards.isEmpty {
            PopupDisclosureCard(
                EntryDetailL10n.staff,
                systemImage: "person.2.fill",
                isExpanded: $isStaffExpanded
            ) {
                horizontalCards(model.staffCards) { card in
                    PersonCardView(card: card)
                }
            }
        }

        switch entry.type {
        case .series:
            if !model.seasonCards.isEmpty {
                LazyVStack(spacing: 18) {
                    ForEach(model.seasonCards) { season in
                        SeriesSeasonEpisodeGroupView(
                            season: season,
                            seriesTMDbID: entry.tmdbID,
                            language: currentLanguage,
                            collapseByDefault: model.collapseSeriesSeasonsByDefault,
                            sectionTitle: season.id == model.seasonCards.first?.id
                                ? EntryDetailL10n.episodes
                                : nil,
                            sectionSystemImage: season.id == model.seasonCards.first?.id
                                ? "play.rectangle.on.rectangle.fill"
                                : nil
                        )
                        .id("\(season.id)-\(model.collapseSeriesSeasonsByDefault)")
                    }
                }
                .id(EntryDetailScrollTarget.episodesSection)
            }
        case .season:
            if !model.episodeCards.isEmpty {
                sectionCard(EntryDetailL10n.episodes, systemImage: "play.rectangle.on.rectangle.fill") {
                    LazyVStack(spacing: 10) {
                        ForEach(model.episodeCards) { episode in
                            EpisodeRowView(
                                card: episode,
                                previewContext: .init(
                                    seriesTMDbID: entry.type.parentSeriesID ?? entry.tmdbID,
                                    seasonNumber: entry.type.seasonNumber ?? 0,
                                    language: currentLanguage
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

        if let errorMessage = model.loadError {
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
            entry: entry,
            scoringEnabled: scoringEnabled,
            isEditingDetails: $isEditingDetails
        )
        .id(EntryDetailScrollTarget.editingSection)
    }

    private var statColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: min(max(model.statCards.count, 1), 3)
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
        dataHandler?.toggleFavorite(entry: entry)
    }

    private func toggleDroppedStatus() {
        withAnimation {
            if entry.watchStatus == .dropped {
                entry.setWatchStatus(.watching)
            } else {
                entry.setWatchStatus(.dropped)
            }
        }
    }

    private var dropActionTitle: LocalizedStringResource {
        entry.watchStatus == .dropped ? EntryDetailL10n.undrop : EntryDetailL10n.markAsDropped
    }

    private var dropActionSystemImage: String {
        entry.watchStatus == .dropped ? "arrow.uturn.backward.circle" : "xmark.circle"
    }

    @ViewBuilder
    private var doneToolbarControl: some View {
        if !shouldConfirmBeforeSaving {
            Button(String(localized: EntryDetailL10n.done)) {
                dismiss()
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
                    dismiss()
                }
            } label: {
                Text(String(localized: EntryDetailL10n.done))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var hasUnsavedUserInfoChanges: Bool {
        entry.userInfoHasChanges(comparedTo: originalUserInfo)
    }

    private var shouldConfirmBeforeSaving: Bool {
        // Onlt non-incremetal note changes require confirmation.
        !entry.notes.hasPrefix(originalUserInfo.notes)
    }

    private func saveAndDismissIfNeeded() {
        if hasUnsavedUserInfoChanges {
            saveUserEdits()
        }
        dismiss()
    }

    private var convertMenuTitle: LocalizedStringResource {
        switch entry.type {
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
            try modelContext.save()
            originalUserInfo = entry.userInfo
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    private func discardUserEdits() {
        entry.updateUserInfo(from: originalUserInfo)
        do {
            try modelContext.save()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isEditingDetails = startInEditingMode
        }
    }

    private func handleConvertTap() async {
        guard !conversion.inProgress else { return }
        switch entry.type {
        case .series:
            await presentSeasonPicker()
        case .season:
            if hasSiblingSeasonEntry {
                presentation.showSiblingSeasonWarning = true
            } else {
                await convertSeasonToSeries()
            }
        case .movie:
            return
        }
    }

    private var hasSiblingSeasonEntry: Bool {
        model.hasSiblingSeasonEntry(for: entry)
    }

    private func presentSeasonPicker() async {
        conversion.isFetchingSeasons = true
        conversion.inProgress = true
        do {
            conversion.seasonNumberOptions = try await model.seasonNumberOptions(
                for: entry,
                language: currentLanguage
            )
            presentation.showSeasonPicker = true
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversion.isFetchingSeasons = false
        conversion.inProgress = false
    }

    private func convertSeasonToSeries() async {
        guard case .season(_, _) = entry.type else { return }
        conversion.inProgress = true
        do {
            try await model.convertSeasonToSeries(
                entry,
                language: currentLanguage
            )
            ToastCenter.global.completionState = .completed(EntryDetailL10n.convertedToSeries)
            dismiss()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversion.inProgress = false
    }

    private func convertSeriesToSeason(seasonNumber: Int) async {
        conversion.inProgress = true
        do {
            try await model.convertSeriesToSeason(
                entry,
                seasonNumber: seasonNumber,
                language: currentLanguage
            )
            ToastCenter.global.completionState = .completed(EntryDetailL10n.convertedToSeason)
            dismiss()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversion.inProgress = false
    }
}

fileprivate struct EntryDetailPreviewHost: View {
    @State private var showDetail = false
    @State private var previewStore = LibraryStore(dataProvider: .forPreview)

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
                        entry: .yourName,
                        repository: previewStore.repository
                    )
                    .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
                }
            }
            .onAppear {
                showDetail = true
            }
        }
    }
}

extension EntryDetailView {
    private static func defaultExpansionState(forKey key: String, defaultValue: Bool) -> Bool {
        UserDefaults.standard.bool(forKey: key, defaultValue: defaultValue)
    }
}

#Preview {
    EntryDetailPreviewHost()
}
