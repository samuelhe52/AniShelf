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
    let entry: AnimeEntry
    private let startInEditingMode: Bool

    @Environment(\.dataHandler) private var dataHandler
    @Environment(\.dismiss) private var dismiss
    @Environment(\.libraryStore) private var libraryStore
    @Environment(\.modelContext) private var modelContext

    @StateObject private var model = EntryDetailModel()
    @State private var showSharingSheet = false
    @State private var showPosterSelectionView = false
    @State private var showCancelEditsConfirmation = false
    @State private var isEditingDetails: Bool
    @State private var originalUserInfo: UserEntryInfo
    @State private var conversionInProgress = false
    @State private var showSeasonPicker = false
    @State private var showSiblingSeasonWarning = false
    @State private var isFetchingSeasons = false
    @State private var seasonNumberOptions: [Int] = []
    @State private var didAutoScrollToEditingSection = false

    private var accentColor: Color { entry.favorite ? .orange : .blue }
    private var currentLanguage: Language { libraryStore?.language ?? .current }
    private let heroHeight: CGFloat = 420

    init(entry: AnimeEntry, startInEditingMode: Bool = false) {
        self.entry = entry
        self.startInEditingMode = startInEditingMode
        self._isEditingDetails = State(initialValue: startInEditingMode)
        self._originalUserInfo = State(initialValue: entry.userInfo)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection

                    VStack(alignment: .leading, spacing: 20) {
                        quickActionsRow
                            .padding(.top, -20)
                            .padding(.bottom, 4)
                        detailsContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
            }
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
        .sheet(isPresented: $showPosterSelectionView) {
            NavigationStack {
                PosterSelectionView(
                    tmdbID: entry.tmdbID,
                    type: entry.type
                ) { url in
                    if url != entry.posterURL {
                        entry.usingCustomPoster = true
                    }
                    entry.posterURL = url
                }
                .navigationTitle("Change Poster")
            }
        }
        .sheet(isPresented: $showSharingSheet) {
            AnimeSharingSheet(entry: entry)
        }
        .confirmationDialog(
            "Convert to which season?",
            isPresented: $showSeasonPicker,
            titleVisibility: .visible
        ) {
            if isFetchingSeasons {
                ProgressView()
            } else if seasonNumberOptions.isEmpty {
                Button("No seasons available", role: .cancel) {}
            } else {
                ForEach(seasonNumberOptions, id: \.self) { seasonNumber in
                    Button("Season \(seasonNumber)") {
                        Task { await convertSeriesToSeason(seasonNumber: seasonNumber) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Discard all changes?", isPresented: $showCancelEditsConfirmation) {
            Button("Discard", role: .destructive) {
                discardUserEdits()
                if startInEditingMode {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Sibling Season Exists", isPresented: $showSiblingSeasonWarning) {
            Button("Convert Anyway", role: .destructive) {
                Task { await convertSeasonToSeries() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Another season entry for this series is already in your library. Converting this season to a series can leave both the series and the sibling season entries in the library."
            )
        }
        .task(id: "\(entry.tmdbID)-\(currentLanguage.rawValue)") {
            await model.load(for: entry, language: currentLanguage, dataHandler: dataHandler)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
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
        .frame(height: heroHeight)
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
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if let url = model.primaryLinkURL ?? entry.linkToDetails {
                Link(destination: url) {
                    Image(systemName: "safari")
                        .font(.title2)
                        .frame(width: 20, height: 20)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }

            PopupActionCircleButton(
                systemImage: "square.and.arrow.up",
                verticalOffset: -1
            ) { showSharingSheet = true }

            PopupActionCircleButton(
                systemImage: entry.favorite ? "heart.fill" : "heart",
                tint: entry.favorite ? .pink : .primary
            ) { toggleFavorite() }

            if entry.type == .movie {
                PopupActionCircleButton(systemImage: "photo.on.rectangle") {
                    showPosterSelectionView = true
                }
            } else {
                Menu {
                    Button {
                        showPosterSelectionView = true
                    } label: {
                        Label("Change Poster", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        Task { await handleConvertTap() }
                    } label: {
                        Label(convertMenuTitle, systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(conversionInProgress)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .frame(width: 20, height: 20)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Details Content

    @ViewBuilder
    private var detailsContent: some View {
        if !model.statCards.isEmpty {
            LazyVGrid(columns: statColumns, spacing: 12) {
                ForEach(model.statCards) { card in
                    DetailStatCard(card: card)
                }
            }
        }

        editingSection

            sectionCard(EntryDetailL10n.overview) {
            Text(model.overviewText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !model.characterCards.isEmpty {
            sectionCard(model.characterSectionTitle) {
                horizontalCards(model.characterCards) { card in
                    CharacterCardView(card: card)
                }
            }
        }

        switch entry.type {
        case .series:
            if !model.seasonCards.isEmpty {
                sectionCard(EntryDetailL10n.episodes) {
                    VStack(spacing: 18) {
                        ForEach(model.seasonCards) { season in
                            SeriesSeasonEpisodeGroupView(
                                season: season,
                                seriesTMDbID: entry.tmdbID,
                                language: currentLanguage
                            )
                        }
                    }
                }
            }
        case .season:
            if !model.episodeCards.isEmpty {
                sectionCard(EntryDetailL10n.episodes) {
                    VStack(spacing: 10) {
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
        PopupDisclosureCard("Tracking", systemImage: "checklist", isExpanded: $isEditingDetails) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Watch Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    AnimeEntryWatchedStatusPicker(for: entry)
                        .pickerStyle(.segmented)
                    AnimeEntryDatePickers(entry: entry)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Notes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    PlaceholderTextEditor(
                        text: Binding(
                            get: { entry.notes },
                            set: { entry.notes = $0 }
                        ),
                        placeholder: "Write some thoughts..."
                    )
                    .frame(height: 180)
                    .padding(12)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    }
                }
            }
        }
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        PopupSectionCard(title) {
            content()
        }
    }

    @ViewBuilder
    private func horizontalCards<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Identifiable {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
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

    @ViewBuilder
    private var doneToolbarControl: some View {
        if entry.userInfoHasChanges(comparedTo: originalUserInfo) {
            Menu {
                Button("Save") {
                    saveUserEdits()
                    dismiss()
                }
                Button("Discard Changes", role: .destructive) {
                    discardUserEdits()
                    dismiss()
                }
            } label: {
                Text(String(localized: EntryDetailL10n.done))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        } else {
            Button(String(localized: EntryDetailL10n.done)) {
                dismiss()
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
        }
    }

    private var convertMenuTitle: LocalizedStringResource {
        switch entry.type {
        case .series:
            "Convert to Season"
        case .season:
            "Convert to Series"
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
        guard !conversionInProgress else { return }
        switch entry.type {
        case .series:
            await presentSeasonPicker()
        case .season:
            if hasSiblingSeasonEntry {
                showSiblingSeasonWarning = true
            } else {
                await convertSeasonToSeries()
            }
        case .movie:
            return
        }
    }

    private var hasSiblingSeasonEntry: Bool {
        guard case .season(_, let parentSeriesID) = entry.type else { return false }

        let visibleSiblingExists =
            libraryStore?.libraryOnDisplay.contains { candidate in
                guard candidate.id != entry.id else { return false }
                guard case .season(_, let candidateParentSeriesID) = candidate.type else {
                    return false
                }
                return candidateParentSeriesID == parentSeriesID
            } ?? false

        if visibleSiblingExists {
            return true
        }

        return entry.parentSeriesEntry?.childSeasonEntries.contains(where: { $0.id != entry.id })
            ?? false
    }

    private func presentSeasonPicker() async {
        isFetchingSeasons = true
        conversionInProgress = true
        do {
            let infoFetcher = InfoFetcher()
            let series = try await infoFetcher.tvSeries(
                entry.tmdbID,
                language: currentLanguage
            )
            seasonNumberOptions = series.seasons?.map(\.seasonNumber).sorted() ?? []
            showSeasonPicker = true
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        isFetchingSeasons = false
        conversionInProgress = false
    }

    private func convertSeasonToSeries() async {
        guard let store = libraryStore else {
            ToastCenter.global.completionState = .failed("Library is unavailable")
            return
        }
        guard case .season(_, _) = entry.type else { return }
        conversionInProgress = true
        do {
            try await store.convertSeasonToSeries(entry, language: currentLanguage)
            ToastCenter.global.completionState = .completed("Converted to series")
            dismiss()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversionInProgress = false
    }

    private func convertSeriesToSeason(seasonNumber: Int) async {
        guard let store = libraryStore else {
            ToastCenter.global.completionState = .failed("Library is unavailable")
            return
        }
        conversionInProgress = true
        do {
            try await store.convertSeriesToSeason(
                entry,
                seasonNumber: seasonNumber,
                language: currentLanguage
            )
            ToastCenter.global.completionState = .completed("Converted to season")
            dismiss()
        } catch {
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
        conversionInProgress = false
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
                    EntryDetailView(entry: .yourName)
                        .environment(\.libraryStore, previewStore)
                        .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
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
