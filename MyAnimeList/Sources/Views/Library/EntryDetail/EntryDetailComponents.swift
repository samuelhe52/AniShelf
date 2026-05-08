//
//  EntryDetailComponents.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

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

struct CharacterCardView: View {
    let card: EntryDetailCharacterCard

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

            Text(card.characterName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(card.actorName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 138, alignment: .leading)
        .padding(12)
        .popupGlassPanel(cornerRadius: 24)
    }
}

struct StaffCardView: View {
    let card: EntryDetailStaffCard

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

            Text(card.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(card.role)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let department = card.department {
                Text(department)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
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
        sectionTitle: LocalizedStringResource? = nil
    ) {
        self.season = season
        self.seriesTMDbID = seriesTMDbID
        self.language = language
        self.sectionTitle = sectionTitle
        _isExpanded = State(initialValue: !collapseByDefault && season.seasonNumber != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sectionTitle {
                Text(sectionTitle)
                    .font(.title3.weight(.bold))
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
