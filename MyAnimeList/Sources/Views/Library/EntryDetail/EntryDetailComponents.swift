//
//  EntryDetailComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

import DataProvider
import Kingfisher
import SwiftUI

struct DetailStatCard: View {
    let card: EntryDetailStatCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: card.symbolName)
                .font(.headline)
                .foregroundStyle(.blue)
            Text(card.value)
                .font(.title3.weight(.bold))
            Text(String(localized: card.title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(16)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct EntryDetailQuickActionsRow: View {
    let detailURL: URL?
    let isFavorite: Bool
    let showsConvertAction: Bool
    let conversionInProgress: Bool
    let convertMenuTitle: () -> LocalizedStringResource
    let dropActionTitle: LocalizedStringResource
    let dropActionSystemImage: String
    let dropActionIsDestructive: Bool
    let onShare: () -> Void
    let onToggleFavorite: () -> Void
    let onChangePoster: () -> Void
    let onConvert: () async -> Void
    let onToggleDroppedStatus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            if let detailURL {
                Link(destination: detailURL) {
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
                verticalOffset: -1,
                action: onShare
            )

            PopupActionCircleButton(
                systemImage: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? .pink : .primary,
                action: onToggleFavorite
            )

            Menu {
                Button(action: onChangePoster) {
                    Label(EntryDetailL10n.changePoster, systemImage: "photo.on.rectangle")
                }

                if showsConvertAction {
                    Button {
                        Task { await onConvert() }
                    } label: {
                        Label(convertMenuTitle(), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(conversionInProgress)
                }

                Divider()

                Button(
                    dropActionTitle,
                    systemImage: dropActionSystemImage,
                    role: dropActionIsDestructive ? .destructive : nil,
                    action: onToggleDroppedStatus
                )
                .tint(dropActionIsDestructive ? .red : .primary)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .frame(width: 20, height: 20)
                    .padding(10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.primary)

            Spacer(minLength: 0)
        }
    }
}

struct EntryScoreCard: View {
    let entry: AnimeEntry

    @State private var bouncingScore: Int?

    private let selectionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.82)
    private let bounceInAnimation = Animation.spring(response: 0.18, dampingFraction: 0.42)
    private let bounceOutAnimation = Animation.spring(response: 0.28, dampingFraction: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label {
                    Text(EntryDetailL10n.score)
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "star")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button {
                    withAnimation(selectionAnimation) {
                        entry.setScore(nil)
                    }
                } label: {
                    Text(EntryDetailL10n.clear)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(entry.score == nil)
                .opacity(entry.score == nil ? 0.42 : 1)
            }

            HStack(spacing: 10) {
                ForEach(Array(AnimeEntry.validScoreRange), id: \.self) { value in
                    scoreButton(for: value)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scoreButton(for value: Int) -> some View {
        let isFilled = (entry.score ?? 0) >= value
        let isBouncing = bouncingScore == value

        return Button {
            setScore(value)
        } label: {
            Image(systemName: isFilled ? "star.fill" : "star")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isFilled ? .yellow : .secondary)
                .scaleEffect(isBouncing ? 1.34 : 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value)/5")
    }

    private func setScore(_ value: Int) {
        withAnimation(selectionAnimation) {
            entry.setScore(value)
        }
        withAnimation(bounceInAnimation) {
            bouncingScore = value
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard bouncingScore == value else { return }
            withAnimation(bounceOutAnimation) {
                bouncingScore = nil
            }
        }
    }
}

struct EntryDetailTrackingSection: View {
    let entry: AnimeEntry
    let scoringEnabled: Bool
    @Binding var isEditingDetails: Bool

    var body: some View {
        Group {
            if scoringEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    EntryScoreCard(entry: entry)
                    Divider()

                    PopupNestedDisclosureSection(
                        EntryDetailL10n.tracking,
                        systemImage: "checklist",
                        isExpanded: $isEditingDetails
                    ) {
                        EntryDetailTrackingEditor(entry: entry)
                    }
                }
                .padding(18)
                .popupGlassPanel(cornerRadius: 24)
            } else {
                PopupDisclosureCard(
                    EntryDetailL10n.tracking,
                    systemImage: "checklist",
                    isExpanded: $isEditingDetails
                ) {
                    EntryDetailTrackingEditor(entry: entry)
                }
            }
        }
    }
}

fileprivate struct EntryDetailTrackingEditor: View {
    let entry: AnimeEntry

    private var dateTrackingButtonLabel: LocalizedStringResource {
        entry.isDateTrackingEnabled ? EntryDetailL10n.hideDates : EntryDetailL10n.trackDates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text(EntryDetailL10n.watchStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Button {
                        withAnimation(.default) {
                            entry.setDateTrackingEnabled(!entry.isDateTrackingEnabled)
                        }
                    } label: {
                        Text(dateTrackingButtonLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                AnimeEntryWatchedStatusPicker(for: entry)
                    .pickerStyle(.segmented)

                if entry.isDateTrackingEnabled {
                    AnimeEntryDatePickers(entry: entry)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(EntryDetailL10n.notes)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                PlaceholderTextEditor(
                    text: Binding(
                        get: { entry.notes },
                        set: { entry.notes = $0 }
                    ),
                    placeholder: EntryDetailL10n.writeSomeThoughts
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
}

struct PersonCardView: View {
    let card: EntryDetailPersonCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let profileURL = card.profileURL {
                    KFImageView(url: profileURL, targetWidth: 240, diskCacheExpiration: .longTerm)
                        .scaledToFill()
                        .frame(width: 122, height: 156)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 122, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(card.primaryText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(card.secondaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 138, alignment: .leading)
        .padding(12)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct EpisodeRowView: View {
    let card: EntryDetailEpisodeCard
    let previewContext: EpisodePreviewContext?
    @State private var showPreview = false
    @State private var previewHapticTrigger = false

    init(card: EntryDetailEpisodeCard, previewContext: EpisodePreviewContext? = nil) {
        self.card = card
        self.previewContext = previewContext
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let imageURL = card.imageURL {
                    KFImageView(url: imageURL, targetWidth: 500, diskCacheExpiration: .transient)
                        .scaledToFill()
                        .frame(width: 126, height: 74)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .overlay {
                            Image(systemName: "tv")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 126, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .popupGlassPanel(cornerRadius: 22)
        .onLongPressGesture {
            guard previewContext != nil else { return }
            previewHapticTrigger.toggle()
            showPreview = true
        }
        .sensoryFeedback(.impact(flexibility: .solid), trigger: previewHapticTrigger)
        .popover(isPresented: $showPreview) {
            if let previewContext {
                EpisodePreviewCard(card: card, context: previewContext)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

struct SeriesSeasonEpisodeGroupView: View {
    let season: EntryDetailSeasonCard
    let seriesTMDbID: Int
    let language: Language
    let sectionTitle: LocalizedStringResource?
    let sectionSystemImage: String?

    private let loadingAnimation: Animation = .easeInOut(duration: 0.25)
    private let initialRenderedEpisodeCount = 24
    private let renderedEpisodeBatchSize = 24

    @State private var isExpanded: Bool
    @State private var episodes: [EntryDetailEpisodeCard] = []
    @State private var renderedEpisodeCount = 24
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var loadedEpisodesKey: String?

    init(
        season: EntryDetailSeasonCard,
        seriesTMDbID: Int,
        language: Language,
        collapseByDefault: Bool = false,
        sectionTitle: LocalizedStringResource? = nil,
        sectionSystemImage: String? = nil
    ) {
        self.season = season
        self.seriesTMDbID = seriesTMDbID
        self.language = language
        self.sectionTitle = sectionTitle
        self.sectionSystemImage = sectionSystemImage
        _isExpanded = State(initialValue: !collapseByDefault && season.seasonNumber != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sectionTitle {
                HStack(spacing: 8) {
                    if let sectionSystemImage {
                        Image(systemName: sectionSystemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(sectionTitle)
                        .font(.title3.weight(.bold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                withAnimation(loadingAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(season.title)
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if season.title != season.subtitle {
                            Text(season.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                episodeListContent
                    .task(id: episodesRequestKey) {
                        await loadEpisodesIfNeeded()
                    }
            }
        }
        .padding(18)
        .popupGlassPanel(cornerRadius: 24)
        .animation(loadingAnimation, value: isLoading)
        .animation(loadingAnimation, value: loadFailed)
        .animation(loadingAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var episodeListContent: some View {
        if episodes.isEmpty, isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .transition(.opacity)
        } else if episodes.isEmpty, loadFailed {
            ContentUnavailableView(
                String(localized: EntryDetailL10n.couldNotLoadDetails),
                systemImage: "wifi.exclamationmark"
            )
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else if episodes.isEmpty, loadedEpisodesKey == episodesRequestKey {
            ContentUnavailableView(
                String(localized: EntryDetailL10n.noEpisodesAvailable),
                systemImage: "list.bullet.rectangle"
            )
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(renderedEpisodes) { episode in
                    EpisodeRowView(
                        card: episode,
                        previewContext: .init(
                            seriesTMDbID: seriesTMDbID,
                            seasonNumber: season.seasonNumber,
                            language: language
                        )
                    )
                }

                if renderedEpisodeCount < episodes.count {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .onAppear {
                            renderMoreEpisodes()
                        }
                }
            }
            .transition(.opacity)
        }
    }

    private var renderedEpisodes: ArraySlice<EntryDetailEpisodeCard> {
        episodes.prefix(renderedEpisodeCount)
    }

    private var episodesRequestKey: String {
        "\(seriesTMDbID)-\(season.id)-\(language.rawValue)"
    }

    private func loadEpisodesIfNeeded() async {
        guard loadedEpisodesKey != episodesRequestKey, !isLoading else { return }
        withAnimation(loadingAnimation) {
            episodes = []
            renderedEpisodeCount = initialRenderedEpisodeCount
            loadFailed = false
            isLoading = true
        }

        do {
            let loadedEpisodes = try await InfoFetcher()
                .seasonEpisodeSummaries(
                    parentSeriesID: seriesTMDbID,
                    seasonNumber: season.seasonNumber,
                    language: language
                )
                .map {
                    EntryDetailEpisodeCard(
                        id: $0.id,
                        episodeNumber: $0.episodeNumber,
                        title: "\($0.episodeNumber). \($0.title)",
                        subtitle: $0.airDate?.formatted(date: .abbreviated, time: .omitted)
                            ?? String(localized: EntryDetailL10n.episode),
                        imageURL: $0.imageURL
                    )
                }
            withAnimation(loadingAnimation) {
                episodes = loadedEpisodes
                renderedEpisodeCount = min(initialRenderedEpisodeCount, loadedEpisodes.count)
                loadedEpisodesKey = episodesRequestKey
                loadFailed = false
                isLoading = false
            }
        } catch {
            withAnimation(loadingAnimation) {
                loadFailed = true
                isLoading = false
            }
        }
    }

    private func renderMoreEpisodes() {
        guard renderedEpisodeCount < episodes.count else { return }
        renderedEpisodeCount = min(renderedEpisodeCount + renderedEpisodeBatchSize, episodes.count)
    }
}

struct EpisodePreviewCard: View {
    let card: EntryDetailEpisodeCard
    let context: EpisodePreviewContext

    @State private var previewModel = EpisodePreviewViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if let imageURL = card.imageURL {
                        KFImageView(url: imageURL, targetWidth: 500, diskCacheExpiration: .transient)
                            .scaledToFill()
                            .frame(width: 126, height: 74)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay {
                                Image(systemName: "tv")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 126, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(card.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(previewModel.overviewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: previewModel.overviewText)
        }
        .frame(width: 320, alignment: .leading)
        .padding(18)
        .popupGlassPanel(cornerRadius: 28, tint: .white.opacity(0.08))
        .task(id: "\(context.seriesTMDbID)-\(context.seasonNumber)-\(card.episodeNumber)-\(context.language.rawValue)")
        {
            await previewModel.load(card: card, context: context)
        }
    }
}
