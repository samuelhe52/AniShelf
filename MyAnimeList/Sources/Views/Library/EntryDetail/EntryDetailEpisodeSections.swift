//
//  EntryDetailEpisodeSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/21.
//

import DataProvider
import Kingfisher
import SwiftUI

@MainActor
@Observable
final class SeriesSeasonEpisodeLoader {
    typealias FetchEpisodes = @Sendable (Int, Int, Language) async throws -> [AnimeEntryEpisodeSummaryDTO]

    private(set) var episodes: [EntryDetailEpisodeCard] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    private(set) var loadedRequestKey: String?

    private let fetchEpisodes: FetchEpisodes
    private var loadGeneration = 0

    init(
        fetchEpisodes: @escaping FetchEpisodes = { seriesTMDbID, seasonNumber, language in
            try await InfoFetcher().seasonEpisodeSummaries(
                parentSeriesID: seriesTMDbID,
                seasonNumber: seasonNumber,
                language: language
            )
        }
    ) {
        self.fetchEpisodes = fetchEpisodes
    }

    func load(
        requestKey: String,
        seriesTMDbID: Int,
        seasonNumber: Int,
        language: Language
    ) async {
        guard !Task.isCancelled, loadedRequestKey != requestKey else { return }

        loadGeneration += 1
        let generation = loadGeneration
        loadedRequestKey = nil
        episodes = []
        loadFailed = false
        isLoading = true

        do {
            let episodeDTOs = try await fetchEpisodes(seriesTMDbID, seasonNumber, language)
            guard loadGeneration == generation else { return }
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            episodes = episodeDTOs.map(SeriesSeasonEpisodeGroupView.episodeCard(from:))
            loadedRequestKey = requestKey
            loadFailed = false
            isLoading = false
        } catch {
            guard loadGeneration == generation else { return }
            if Task.isCancelled || Self.isCancellation(error) {
                isLoading = false
                return
            }
            loadFailed = true
            isLoading = false
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

struct SeriesSeasonEpisodeGroupView: View {
    let season: EntryDetailSeasonCard
    let seriesTMDbID: Int
    let language: Language
    let watchStatus: AnimeEntry.WatchStatus
    let episodeProgressSummary: AnimeEntryEpisodeProgressSummary?
    let sectionTitle: LocalizedStringResource?
    let sectionSystemImage: String?

    private let loadingAnimation: Animation = .easeInOut(duration: 0.25)
    private let initialRenderedEpisodeCount = 24
    private let renderedEpisodeBatchSize = 24

    @State private var isExpanded: Bool
    @State private var episodeLoader = SeriesSeasonEpisodeLoader()
    @State private var renderedEpisodeCount = 24

    init(
        season: EntryDetailSeasonCard,
        seriesTMDbID: Int,
        language: Language,
        watchStatus: AnimeEntry.WatchStatus,
        episodeProgressSummary: AnimeEntryEpisodeProgressSummary? = nil,
        collapseByDefault: Bool = false,
        sectionTitle: LocalizedStringResource? = nil,
        sectionSystemImage: String? = nil
    ) {
        self.season = season
        self.seriesTMDbID = seriesTMDbID
        self.language = language
        self.watchStatus = watchStatus
        self.episodeProgressSummary = episodeProgressSummary
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
        .animation(loadingAnimation, value: episodeLoader.isLoading)
        .animation(loadingAnimation, value: episodeLoader.loadFailed)
        .animation(loadingAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var episodeListContent: some View {
        if episodeLoader.episodes.isEmpty, episodeLoader.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .transition(.opacity)
        } else if episodeLoader.episodes.isEmpty, episodeLoader.loadFailed {
            ContentUnavailableView(
                String(localized: EntryDetailL10n.couldNotLoadDetails),
                systemImage: "wifi.exclamationmark"
            )
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else if episodeLoader.episodes.isEmpty,
            episodeLoader.loadedRequestKey == episodesRequestKey
        {
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
                        ),
                        isWatched: EntryDetailEpisodePresentation.isEpisodeWatched(
                            episode.episodeNumber,
                            inSeason: season.seasonNumber,
                            watchStatus: watchStatus,
                            summary: episodeProgressSummary
                        )
                    )
                }

                if renderedEpisodeCount < episodeLoader.episodes.count {
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
        episodeLoader.episodes.prefix(renderedEpisodeCount)
    }

    private var episodesRequestKey: String {
        "\(seriesTMDbID)-\(season.id)-\(language.rawValue)"
    }

    private func loadEpisodesIfNeeded() async {
        let requestKey = episodesRequestKey
        renderedEpisodeCount = initialRenderedEpisodeCount
        await episodeLoader.load(
            requestKey: requestKey,
            seriesTMDbID: seriesTMDbID,
            seasonNumber: season.seasonNumber,
            language: language
        )
        guard episodeLoader.loadedRequestKey == requestKey else { return }
        renderedEpisodeCount = min(initialRenderedEpisodeCount, episodeLoader.episodes.count)
    }

    static func episodeCard(from dto: AnimeEntryEpisodeSummaryDTO) -> EntryDetailEpisodeCard {
        EntryDetailEpisodeCard(
            id: dto.id,
            episodeNumber: dto.episodeNumber,
            title: "\(dto.episodeNumber). \(dto.title)",
            subtitle: dto.airDate?.formatted(date: .abbreviated, time: .omitted)
                ?? String(localized: EntryDetailL10n.episode),
            imageURL: dto.resolvedImageURL
        )
    }

    private func renderMoreEpisodes() {
        guard renderedEpisodeCount < episodeLoader.episodes.count else { return }
        renderedEpisodeCount = min(
            renderedEpisodeCount + renderedEpisodeBatchSize,
            episodeLoader.episodes.count
        )
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

            if !previewModel.staffRows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(EntryDetailL10n.staff)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(previewModel.staffRows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(row.role)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Text(row.names)
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: 320, alignment: .leading)
        .padding(18)
        .task(id: taskID) {
            await previewModel.load(card: card, context: context)
        }
    }

    private var taskID: String {
        "\(context.seriesTMDbID)-\(context.seasonNumber)-\(card.episodeNumber)-\(context.language.rawValue)"
    }
}
