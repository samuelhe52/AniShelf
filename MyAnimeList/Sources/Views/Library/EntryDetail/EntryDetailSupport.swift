//
//  EntryDetailSupport.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/4/4.
//

import DataProvider
import SwiftUI

@MainActor
final class EntryDetailModel: ObservableObject {
    struct StatCard: Identifiable {
        let id: String
        let title: LocalizedStringResource
        let value: String
        let symbolName: String
    }

    struct CharacterCard: Identifiable {
        let id: Int
        let characterName: String
        let actorName: String
        let profileURL: URL?
    }

    struct SeasonCard: Identifiable {
        let id: Int
        let seasonNumber: Int
        let title: String
        let subtitle: String
        let posterURL: URL?
    }

    struct EpisodeCard: Identifiable, Equatable {
        let id: Int
        let episodeNumber: Int
        let title: String
        let subtitle: String
        let imageURL: URL?
    }

    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var heroImageURL: URL?
    @Published private(set) var logoImageURL: URL?
    @Published private(set) var primaryLinkURL: URL?
    @Published private(set) var displayTitle = ""
    @Published private(set) var subtitleText: String?
    @Published private(set) var metadataLineItems: [String] = []
    @Published private(set) var overviewText = String(localized: EntryDetailL10n.noOverviewAvailable)
    @Published private(set) var genreNames: [String] = []
    @Published private(set) var statCards: [StatCard] = []
    @Published private(set) var characterCards: [CharacterCard] = []
    @Published private(set) var seasonCards: [SeasonCard] = []
    @Published private(set) var episodeCards: [EpisodeCard] = []
    @Published private(set) var characterSectionTitle: LocalizedStringResource =
        EntryDetailL10n.characters

    private var lastRequestKey: String?

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
        seasonCards = []
        episodeCards = []
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
            let detail = try await InfoFetcher().detailInfo(
                entryType: entry.type,
                tmdbID: entry.tmdbID,
                language: language
            )
            entry.detail = detail
            try? dataHandler?.modelContext.save()
            apply(detail: detail, entry: entry, language: language)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func apply(detail: AnimeEntryDetail, entry: AnimeEntry, language: Language) {
        displayTitle = detail.title
        subtitleText = detail.subtitle
        overviewText = detail.overview ?? entry.displayOverview
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
                    detail.status,
                ].compactMap(\.self)
            case .series:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.status,
                    detail.seasonCount.map(Self.seasonCountText),
                ].compactMap(\.self)
            case .season:
                [
                    detail.airDate?.formatted(date: .abbreviated, time: .omitted),
                    detail.episodeCount.map(Self.episodeCountText),
                    detail.status,
                ].compactMap(\.self)
            }

        statCards =
            switch entry.type {
            case .movie:
                [
                    detail.voteAverage.map {
                        StatCard(
                            id: "rating",
                            title: EntryDetailL10n.tmdbScore,
                            value: String(format: "%.1f", $0),
                            symbolName: "star.fill"
                        )
                    },
                    detail.runtimeMinutes.map {
                        StatCard(
                            id: "runtime",
                            title: EntryDetailL10n.runtime,
                            value: Self.minutesText($0),
                            symbolName: "clock.fill"
                        )
                    },
                ].compactMap(\.self)
            case .series, .season:
                [
                    detail.voteAverage.map {
                        StatCard(
                            id: "rating",
                            title: EntryDetailL10n.tmdbScore,
                            value: String(format: "%.1f", $0),
                            symbolName: "star.fill"
                        )
                    },
                    detail.episodeCount.map {
                        StatCard(
                            id: "episodes",
                            title: EntryDetailL10n.episodes,
                            value: "\($0)",
                            symbolName: "play.rectangle.fill"
                        )
                    },
                    detail.runtimeMinutes.map {
                        StatCard(
                            id: "runtime",
                            title: EntryDetailL10n.averageRuntime,
                            value: Self.minutesText($0),
                            symbolName: "clock.fill"
                        )
                    },
                ].compactMap(\.self)
            }

        characterCards = detail.characters.map {
            CharacterCard(
                id: $0.id,
                characterName: $0.characterName,
                actorName: $0.actorName,
                profileURL: $0.profileURL
            )
        }
        seasonCards = detail.seasons.map {
            SeasonCard(
                id: $0.id,
                seasonNumber: $0.seasonNumber,
                title: $0.title,
                subtitle: Self.seasonLabelText($0.seasonNumber),
                posterURL: $0.posterURL
            )
        }
        episodeCards = detail.episodes.map {
            EpisodeCard(
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
        String(localized: "Season \(seasonNumber)")
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
        10770: "TV Movie",
    ]

    private static let japaneseGenreNames: [Int: String] = [
        12: "アドベンチャー", 14: "ファンタジー", 16: "アニメーション", 18: "ドラマ", 27: "ホラー",
        28: "アクション", 35: "コメディ", 36: "歴史", 37: "西部劇", 53: "スリラー",
        80: "犯罪", 99: "ドキュメンタリー", 878: "SF", 9648: "ミステリー", 10402: "音楽",
        10749: "ロマンス", 10751: "ファミリー", 10752: "戦争",
        10759: "アクション・アドベンチャー", 10762: "キッズ", 10763: "ニュース",
        10764: "リアリティ", 10765: "SF・ファンタジー", 10766: "ソープ",
        10767: "トーク", 10768: "戦争・政治", 10770: "テレビ映画",
    ]

    private static let chineseGenreNames: [Int: String] = [
        12: "冒险", 14: "奇幻", 16: "动画", 18: "剧情", 27: "恐怖", 28: "动作", 35: "喜剧",
        36: "历史", 37: "西部", 53: "惊悚", 80: "犯罪", 99: "纪录", 878: "科幻", 9648: "悬疑",
        10402: "音乐", 10749: "爱情", 10751: "家庭", 10752: "战争", 10759: "动作冒险",
        10762: "儿童", 10763: "新闻", 10764: "真人秀", 10765: "科幻奇幻",
        10766: "肥皂剧", 10767: "脱口秀", 10768: "战争政治", 10770: "电视电影",
    ]
}

struct EpisodePreviewContext {
    let seriesTMDbID: Int
    let seasonNumber: Int
    let language: Language
}

@MainActor
final class EpisodePreviewModel: ObservableObject {
    private let detailLoadAnimation: Animation = .easeInOut(duration: 0.3)

    @Published private(set) var overviewText = String(localized: EntryDetailL10n.loading)
    @Published private(set) var isLoading = false

    private var lastRequestKey: String?

    func load(card: EntryDetailModel.EpisodeCard, context: EpisodePreviewContext) async {
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

enum EntryDetailL10n {
    static let loading: LocalizedStringResource = "Loading..."
    static let done: LocalizedStringResource = "Done"
    static let showDetail: LocalizedStringResource = "Show Detail"
    static let overview: LocalizedStringResource = "Overview"
    static let episodes: LocalizedStringResource = "Episodes"
    static let characters: LocalizedStringResource = "Characters"
    static let tmdb: LocalizedStringResource = "TMDb"
    static let couldNotLoadDetails: LocalizedStringResource = "Couldn't load details"
    static let noOverviewAvailable: LocalizedStringResource = "No overview available."
    static let tmdbScore: LocalizedStringResource = "TMDb Score"
    static let runtime: LocalizedStringResource = "Runtime"
    static let averageRuntime: LocalizedStringResource = "Avg Runtime"
    static let episode: LocalizedStringResource = "Episode"
}

enum EntryDetailScrollTarget: Hashable {
    case editingSection
}
