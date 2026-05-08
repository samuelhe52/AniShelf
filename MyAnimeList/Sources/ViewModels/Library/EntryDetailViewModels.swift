//
//  EntryDetailViewModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/6.
//

import DataProvider
import Observation
import SwiftUI

@MainActor
@Observable
final class EntryDetailViewModel {
    private let repository: LibraryRepository
    private let infoFetcher: InfoFetcher

    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var heroImageURL: URL?
    private(set) var logoImageURL: URL?
    private(set) var primaryLinkURL: URL?
    private(set) var displayTitle = ""
    private(set) var subtitleText: String?
    private(set) var metadataLineItems: [String] = []
    private(set) var overviewText = String(localized: EntryDetailL10n.noOverviewAvailable)
    private(set) var genreNames: [String] = []
    private(set) var statCards: [EntryDetailStatCard] = []
    private(set) var characterCards: [EntryDetailPersonCard] = []
    private(set) var staffCards: [EntryDetailPersonCard] = []
    private(set) var seasonCards: [EntryDetailSeasonCard] = []
    private(set) var episodeCards: [EntryDetailEpisodeCard] = []
    private(set) var collapseSeriesSeasonsByDefault = false
    private(set) var characterSectionTitle: LocalizedStringResource =
        EntryDetailL10n.characters

    private var lastRequestKey: String?

    init(repository: LibraryRepository, infoFetcher: InfoFetcher = .init()) {
        self.repository = repository
        self.infoFetcher = infoFetcher
    }

    func load(for entry: AnimeEntry, language: Language, dataHandler: DataHandler?) async {
        let requestKey = "\(entry.tmdbID)-\(language.rawValue)"
        guard lastRequestKey != requestKey else { return }
        lastRequestKey = requestKey

        displayTitle = entry.displayName
        subtitleText = nil
        metadataLineItems = []
        overviewText = entry.displayOverview ?? String(localized: EntryDetailL10n.noOverviewAvailable)
        genreNames = []
        statCards = []
        characterCards = []
        staffCards = []
        seasonCards = []
        episodeCards = []
        collapseSeriesSeasonsByDefault = false
        characterSectionTitle = EntryDetailL10n.characters
        primaryLinkURL = entry.linkToDetails
        heroImageURL = entry.backdropURL ?? entry.posterURL
        logoImageURL = nil
        loadError = nil
        if let detail = entry.detail, detail.language == language.rawValue {
            apply(detail: detail, entry: entry, language: language)
            if detail.logoImageURL != nil {
                isLoading = false
                return
            }
        }

        isLoading = true
        do {
            let detailDTO = try await infoFetcher.detailInfo(
                entryType: entry.type,
                tmdbID: entry.tmdbID,
                language: language
            )
            let detail = entry.replaceDetail(from: detailDTO)
            try? dataHandler?.modelContext.save()
            apply(detail: detail, entry: entry, language: language)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func hasSiblingSeasonEntry(for entry: AnimeEntry) -> Bool {
        guard case .season(_, let parentSeriesID) = entry.type else { return false }

        do {
            let visibleSiblingExists = try repository.visibleLibraryEntries().contains { candidate in
                guard candidate.id != entry.id else { return false }
                guard case .season(_, let candidateParentSeriesID) = candidate.type else {
                    return false
                }
                return candidateParentSeriesID == parentSeriesID
            }

            if visibleSiblingExists {
                return true
            }
        } catch {
            libraryStoreLogger.warning(
                "Failed to check sibling season entries for \(entry.tmdbID, privacy: .public): \(error.localizedDescription)"
            )
        }

        return entry.parentSeriesEntry?.childSeasonEntries.contains(where: { $0.id != entry.id })
            ?? false
    }

    func seasonNumberOptions(for entry: AnimeEntry, language: Language) async throws -> [Int] {
        let series = try await infoFetcher.tvSeries(
            entry.tmdbID,
            language: language
        )
        return series.seasons?.map(\.seasonNumber).sorted() ?? []
    }

    func convertSeasonToSeries(_ entry: AnimeEntry, language: Language) async throws {
        let converter = LibraryEntryConverter(repository: repository)
        try await converter.convertSeasonToSeries(
            entry,
            language: language,
            fetcher: infoFetcher
        )
    }

    func convertSeriesToSeason(
        _ entry: AnimeEntry,
        seasonNumber: Int,
        language: Language
    ) async throws {
        let converter = LibraryEntryConverter(repository: repository)
        try await converter.convertSeriesToSeason(
            entry,
            seasonNumber: seasonNumber,
            language: language,
            fetcher: infoFetcher
        )
    }

    private func apply(detail: AnimeEntryDetail, entry: AnimeEntry, language: Language) {
        displayTitle = detail.title
        subtitleText = detail.subtitle
        overviewText =
            detail.overview ?? entry.displayOverview
            ?? String(localized: EntryDetailL10n.noOverviewAvailable)
        genreNames = Self.localizedGenreNames(detail.genreIDs, language: language)
        heroImageURL = detail.heroImageURL ?? entry.backdropURL ?? entry.posterURL
        logoImageURL = detail.logoImageURL
        primaryLinkURL = detail.primaryLinkURL ?? entry.linkToDetails
        characterSectionTitle = EntryDetailL10n.characters

        metadataLineItems =
            switch entry.type {
            case .movie:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.runtimeMinutes.map(Self.minutesText),
                    detail.status
                ].compactMap(\.self)
            case .series:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.status,
                    detail.seasonCount.map(Self.seasonCountText)
                ].compactMap(\.self)
            case .season:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.episodeCount.map(Self.episodeCountText),
                    detail.status
                ].compactMap(\.self)
            }

        statCards =
            switch entry.type {
            case .movie:
                [
                    detail.voteAverage.map {
                        EntryDetailStatCard(
                            id: "rating",
                            title: EntryDetailL10n.tmdbScore,
                            value: String(format: "%.1f", $0),
                            symbolName: "star.fill"
                        )
                    },
                    detail.runtimeMinutes.map {
                        EntryDetailStatCard(
                            id: "runtime",
                            title: EntryDetailL10n.runtime,
                            value: Self.minutesText($0),
                            symbolName: "clock.fill"
                        )
                    }
                ].compactMap(\.self)
            case .series, .season:
                [
                    detail.voteAverage.map {
                        EntryDetailStatCard(
                            id: "rating",
                            title: EntryDetailL10n.tmdbScore,
                            value: String(format: "%.1f", $0),
                            symbolName: "star.fill"
                        )
                    },
                    detail.episodeCount.map {
                        EntryDetailStatCard(
                            id: "episodes",
                            title: EntryDetailL10n.episodes,
                            value: "\($0)",
                            symbolName: "play.rectangle.fill"
                        )
                    },
                    detail.runtimeMinutes.map {
                        EntryDetailStatCard(
                            id: "runtime",
                            title: EntryDetailL10n.averageRuntime,
                            value: Self.minutesText($0),
                            symbolName: "clock.fill"
                        )
                    }
                ].compactMap(\.self)
            }

        characterCards = detail.characters.map {
            EntryDetailPersonCard(
                id: $0.id,
                primaryText: $0.characterName,
                secondaryText: $0.actorName,
                profileURL: $0.profileURL
            )
        }
        staffCards = detail.staff.map {
            EntryDetailPersonCard(
                id: $0.id,
                primaryText: $0.name,
                secondaryText: $0.role,
                profileURL: $0.profileURL
            )
        }
        seasonCards = detail.seasons.map {
            EntryDetailSeasonCard(
                id: $0.id,
                seasonNumber: $0.seasonNumber,
                title: $0.title,
                subtitle: Self.seasonLabelText($0.seasonNumber),
                posterURL: $0.posterURL
            )
        }
        collapseSeriesSeasonsByDefault =
            entry.type == .series
            && EntryDetailSeasonExpansionPolicy.shouldCollapseSeriesSeasonsByDefault(
                episodeCount: detail.episodeCount,
                seasonCount: detail.seasonCount,
                seasonCardCount: seasonCards.count
            )
        episodeCards = detail.episodes.map {
            EntryDetailEpisodeCard(
                id: $0.id,
                episodeNumber: $0.episodeNumber,
                title: "\($0.episodeNumber). \($0.title)",
                subtitle: $0.airDate?.formatted(date: .abbreviated, time: .omitted)
                    ?? String(localized: EntryDetailL10n.episode),
                imageURL: $0.imageURL
            )
        }
    }

    private static func seasonCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "\(count) season")
            : String(localized: "\(count) seasons")
    }

    private static func episodeCountText(_ count: Int) -> String {
        String(localized: "\(count) episodes")
    }

    private static func seasonLabelText(_ seasonNumber: Int) -> String {
        if seasonNumber == 0 {
            return String(localized: "Specials")
        }
        return String(localized: "Season \(seasonNumber)")
    }

    private static func minutesText(_ minutes: Int) -> String {
        String(localized: "\(minutes) min")
    }

    private static func localizedGenreNames(_ genreIDs: [Int], language: Language) -> [String] {
        genreIDs.compactMap { localizedGenreName(for: $0, language: language) }
    }

    private static func localizedGenreName(for genreID: Int, language: Language) -> String? {
        switch language {
        case .english:
            englishGenreNames[genreID]
        case .japanese:
            japaneseGenreNames[genreID]
        case .chinese:
            chineseGenreNames[genreID]
        }
    }

    private static let englishGenreNames: [Int: String] = [
        12: "Adventure", 14: "Fantasy", 16: "Animation", 18: "Drama", 27: "Horror",
        28: "Action", 35: "Comedy", 36: "History", 37: "Western", 53: "Thriller",
        80: "Crime", 99: "Documentary", 878: "Science Fiction", 9648: "Mystery",
        10402: "Music", 10749: "Romance", 10751: "Family", 10752: "War",
        10759: "Action & Adventure", 10762: "Kids", 10763: "News", 10764: "Reality",
        10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics",
        10770: "TV Movie"
    ]

    private static let japaneseGenreNames: [Int: String] = [
        12: "アドベンチャー", 14: "ファンタジー", 16: "アニメーション", 18: "ドラマ", 27: "ホラー",
        28: "アクション", 35: "コメディ", 36: "歴史", 37: "西部劇", 53: "スリラー",
        80: "犯罪", 99: "ドキュメンタリー", 878: "SF", 9648: "ミステリー", 10402: "音楽",
        10749: "ロマンス", 10751: "ファミリー", 10752: "戦争",
        10759: "アクション・アドベンチャー", 10762: "キッズ", 10763: "ニュース",
        10764: "リアリティ", 10765: "SF・ファンタジー", 10766: "ソープ",
        10767: "トーク", 10768: "戦争・政治", 10770: "テレビ映画"
    ]

    private static let chineseGenreNames: [Int: String] = [
        12: "冒险", 14: "奇幻", 16: "动画", 18: "剧情", 27: "恐怖", 28: "动作", 35: "喜剧",
        36: "历史", 37: "西部", 53: "惊悚", 80: "犯罪", 99: "纪录", 878: "科幻", 9648: "悬疑",
        10402: "音乐", 10749: "爱情", 10751: "家庭", 10752: "战争", 10759: "动作冒险",
        10762: "儿童", 10763: "新闻", 10764: "真人秀", 10765: "科幻奇幻",
        10766: "肥皂剧", 10767: "脱口秀", 10768: "战争政治", 10770: "电视电影"
    ]
}

@MainActor
@Observable
final class EpisodePreviewViewModel {
    private let detailLoadAnimation: Animation = .easeInOut(duration: 0.3)

    private(set) var overviewText = String(localized: EntryDetailL10n.loading)
    private(set) var isLoading = false

    private var lastRequestKey: String?

    func load(card: EntryDetailEpisodeCard, context: EpisodePreviewContext) async {
        let requestKey =
            "\(context.seriesTMDbID)-\(context.seasonNumber)-\(card.episodeNumber)-\(context.language.rawValue)"
        guard lastRequestKey != requestKey else { return }
        lastRequestKey = requestKey
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try await InfoFetcher().episodePreviewInfo(
                parentSeriesID: context.seriesTMDbID,
                seasonNumber: context.seasonNumber,
                episodeNumber: card.episodeNumber,
                language: context.language
            )
            let resolvedOverviewText =
                detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? detail.overview!
                : String(localized: EntryDetailL10n.noOverviewAvailable)
            withAnimation(detailLoadAnimation) {
                overviewText = resolvedOverviewText
            }
        } catch {
            withAnimation(detailLoadAnimation) {
                overviewText = String(localized: EntryDetailL10n.noOverviewAvailable)
            }
        }
    }
}
