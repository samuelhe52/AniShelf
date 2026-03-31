//
//  EntryDetailView.swift
//  MyAnimeList
//
//  Created by Samuel He on 8/1/25.
//

import DataProvider
import SwiftUI
import TMDb

struct EntryDetailView: View {
    let entry: AnimeEntry

    @Environment(\.dataHandler) private var dataHandler
    @Environment(\.dismiss) private var dismiss
    @Environment(\.libraryStore) private var libraryStore

    @StateObject private var model = EntryDetailModel()
    @State private var showEditor = false
    @State private var showSharingSheet = false

    private var accentColor: Color { entry.favorite ? .orange : .blue }
    private var currentLanguage: Language { libraryStore?.language ?? .current }
    private let heroHeight: CGFloat = 420

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection

                VStack(alignment: .leading, spacing: 20) {
                    quickActionsRow
                    detailsContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground))
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarContent }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                AnimeEntryEditor(entry: entry)
            }
        }
        .sheet(isPresented: $showSharingSheet) {
            AnimeSharingSheet(entry: entry)
        }
        .task(id: "\(entry.tmdbID)-\(currentLanguage.rawValue)") {
            await model.load(for: entry, language: currentLanguage)
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

            circleActionButton("square.and.pencil") { showEditor = true }

            circleActionButton(
                entry.favorite ? "heart.fill" : "heart",
                tint: entry.favorite ? .pink : .primary
            ) { toggleFavorite() }

            circleActionButton("square.and.arrow.up", verticalOffset: -1) { showSharingSheet = true }

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

            Spacer(minLength: 0)
        }
    }

    private func circleActionButton(
        _ icon: String,
        tint: Color = .primary,
        verticalOffset: CGFloat = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 20, height: 20)
                .padding(10)
                .offset(y: verticalOffset)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(tint)
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

        sectionCard(L10n.overview) {
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

        if !model.seasonCards.isEmpty {
            sectionCard(L10n.seasons) {
                horizontalCards(model.seasonCards) { season in
                    SeasonCardView(card: season, accentColor: accentColor)
                }
            }
        }

        if !model.episodeCards.isEmpty {
            sectionCard(L10n.episodes) {
                VStack(spacing: 10) {
                    ForEach(model.episodeCards) { episode in
                        EpisodeRowView(card: episode)
                    }
                }
            }
        }

        if let errorMessage = model.loadError {
            sectionCard(L10n.tmdb) {
                ContentUnavailableView(
                    String(localized: L10n.couldNotLoadDetails),
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity)
            }
        }
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
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: title))
                .font(.title3.weight(.bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 24)
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
            Button(String(localized: L10n.done)) {
                dismiss()
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Actions

    private func toggleFavorite() {
        dataHandler?.toggleFavorite(entry: entry)
    }
}

@MainActor
private final class EntryDetailModel: ObservableObject {
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
        let title: String
        let subtitle: String
        let posterURL: URL?
    }

    struct EpisodeCard: Identifiable {
        let id: Int
        let title: String
        let subtitle: String
        let imageURL: URL?
    }

    private enum Payload {
        case movie(Movie)
        case series(TVSeries)
        case season(parentSeries: TVSeries, season: TVSeason)
    }

    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var heroImageURL: URL?
    @Published private(set) var logoImageURL: URL?
    @Published private(set) var primaryLinkURL: URL?
    @Published private(set) var displayTitle = ""
    @Published private(set) var subtitleText: String?
    @Published private(set) var metadataLineItems: [String] = []
    @Published private(set) var overviewText = String(localized: L10n.noOverviewAvailable)
    @Published private(set) var genreNames: [String] = []
    @Published private(set) var statCards: [StatCard] = []
    @Published private(set) var characterCards: [CharacterCard] = []
    @Published private(set) var seasonCards: [SeasonCard] = []
    @Published private(set) var episodeCards: [EpisodeCard] = []
    @Published private(set) var characterSectionTitle: LocalizedStringResource = L10n.characters

    private var lastRequestKey: String?

    func load(for entry: AnimeEntry, language: Language) async {
        let requestKey = "\(entry.tmdbID)-\(language.rawValue)"
        guard lastRequestKey != requestKey else { return }
        lastRequestKey = requestKey

        displayTitle = entry.displayName
        subtitleText = nil
        metadataLineItems = []
        overviewText = entry.displayOverview ?? String(localized: L10n.noOverviewAvailable)
        genreNames = []
        statCards = []
        characterCards = []
        seasonCards = []
        episodeCards = []
        characterSectionTitle = L10n.characters
        primaryLinkURL = entry.linkToDetails
        heroImageURL = entry.backdropURL ?? entry.posterURL
        logoImageURL = nil
        loadError = nil
        isLoading = true

        do {
            let fetcher = InfoFetcher()
            let payload = try await fetchPayload(for: entry, language: language, fetcher: fetcher)
            try await apply(payload: payload, entry: entry, client: fetcher.tmdbClient, language: language)
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchPayload(for entry: AnimeEntry, language: Language, fetcher: InfoFetcher) async throws
        -> Payload
    {
        switch entry.type {
        case .movie:
            return .movie(try await fetcher.movie(entry.tmdbID, language: language))
        case .series:
            return .series(try await fetcher.tvSeries(entry.tmdbID, language: language))
        case .season(let seasonNumber, let parentSeriesID):
            async let parentSeries = fetcher.tvSeries(parentSeriesID, language: language)
            async let season = fetcher.tvSeason(parentSeriesID, seasonNumber: seasonNumber, language: language)
            return try await .season(parentSeries: parentSeries, season: season)
        }
    }

    private func apply(payload: Payload, entry: AnimeEntry, client: TMDbClient, language: Language) async throws {
        switch payload {
        case .movie(let movie):
            displayTitle = movie.title
            subtitleText = movie.tagline?.nilIfEmpty
            metadataLineItems = [
                movie.releaseDate?.formatted(date: .abbreviated, time: .omitted),
                movie.runtime.map(Self.minutesText),
                movie.status?.rawValue,
            ].compactMap(\.self)
            overviewText =
                movie.overview?.nilIfEmpty
                ?? entry.displayOverview
                ?? String(localized: L10n.noOverviewAvailable)
            genreNames = Self.localizedGenreNames(movie.genres, language: language)
            statCards = [
                movie.voteAverage.map {
                    StatCard(id: "rating", title: L10n.tmdbScore, value: String(format: "%.1f", $0), symbolName: "star.fill")
                },
                movie.runtime.map {
                    StatCard(id: "runtime", title: L10n.runtime, value: Self.minutesText($0), symbolName: "clock.fill")
                },
            ]
            .compactMap(\.self)
            heroImageURL = try await movie.backdropURL(client: client, idealWidth: 1_280) ?? entry.posterURL
            logoImageURL = try await movie.logoURL(client: client, idealWidth: 500)
            primaryLinkURL = movie.homepageURL ?? entry.linkToDetails

            let credits = try await client.movies.credits(forMovie: movie.id, language: language.rawValue)
            characterCards = try await makeCharacterCards(
                from: credits.cast.prefix(12),
                client: client,
                language: language
            )

        case .series(let series):
            displayTitle = series.name
            subtitleText = series.tagline?.nilIfEmpty
            metadataLineItems = [
                series.firstAirDate?.formatted(date: .abbreviated, time: .omitted),
                series.status,
                series.numberOfSeasons.map(Self.seasonCountText),
            ].compactMap(\.self)
            overviewText =
                series.overview?.nilIfEmpty
                ?? entry.displayOverview
                ?? String(localized: L10n.noOverviewAvailable)
            genreNames = Self.localizedGenreNames(series.genres, language: language)
            statCards = [
                series.voteAverage.map {
                    StatCard(id: "rating", title: L10n.tmdbScore, value: String(format: "%.1f", $0), symbolName: "star.fill")
                },
                series.numberOfEpisodes.map {
                    StatCard(id: "episodes", title: L10n.episodes, value: "\($0)", symbolName: "play.rectangle.fill")
                },
                series.episodeRunTime?.first.map {
                    StatCard(id: "runtime", title: L10n.averageRuntime, value: Self.minutesText($0), symbolName: "clock.fill")
                },
            ]
            .compactMap(\.self)
            heroImageURL = try await series.backdropURL(client: client, idealWidth: 1_280) ?? entry.posterURL
            logoImageURL = try await series.logoURL(client: client, idealWidth: 500)
            primaryLinkURL = series.homepageURL ?? entry.linkToDetails
            seasonCards = try await makeSeasonCards(from: series.seasons ?? [], client: client)

            let credits = try await client.tvSeries.aggregateCredits(
                forTVSeries: series.id,
                language: language.rawValue
            )
            characterCards = try await makeCharacterCards(
                from: credits.cast.prefix(12),
                client: client,
                language: language
            )

        case .season(let parentSeries, let season):
            displayTitle = parentSeries.name
            subtitleText = season.name
            metadataLineItems = [
                season.airDate?.formatted(date: .abbreviated, time: .omitted),
                season.episodes.map { Self.episodeCountText($0.count) },
                parentSeries.status,
            ].compactMap(\.self)
            overviewText =
                season.overview?.nilIfEmpty
                ?? entry.displayOverview
                ?? String(localized: L10n.noOverviewAvailable)
            genreNames = Self.localizedGenreNames(parentSeries.genres, language: language)
            statCards = [
                parentSeries.voteAverage.map {
                    StatCard(id: "rating", title: L10n.tmdbScore, value: String(format: "%.1f", $0), symbolName: "star.fill")
                },
                season.episodes.map {
                    StatCard(id: "episodes", title: L10n.episodes, value: "\($0.count)", symbolName: "play.rectangle.fill")
                },
                parentSeries.episodeRunTime?.first.map {
                    StatCard(id: "runtime", title: L10n.averageRuntime, value: Self.minutesText($0), symbolName: "clock.fill")
                },
            ]
            .compactMap(\.self)
            heroImageURL = try await parentSeries.backdropURL(client: client, idealWidth: 1_280) ?? entry.posterURL
            logoImageURL = try await parentSeries.logoURL(client: client, idealWidth: 500)
            primaryLinkURL = parentSeries.homepageURL ?? entry.linkToDetails
            episodeCards = try await makeEpisodeCards(from: Array((season.episodes ?? []).prefix(8)), client: client)

            let credits = try await client.tvSeasons.aggregateCredits(
                forSeason: season.seasonNumber,
                inTVSeries: parentSeries.id,
                language: language.rawValue
            )
            characterCards = try await makeCharacterCards(
                from: credits.cast.prefix(12),
                client: client,
                language: language
            )
        }
    }

    private func makeCharacterCards<S: Sequence>(
        from cast: S,
        client: TMDbClient,
        language: Language
    ) async throws -> [CharacterCard] where S.Element == CastMember {
        let imagesConfiguration = try await client.imagesConfiguration
        return cast.map {
            CharacterCard(
                id: $0.id,
                characterName: $0.character.strippingVoiceQualifier.nilIfEmpty ?? String(localized: L10n.character),
                actorName: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: nil,
                    language: language
                ),
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    private func makeCharacterCards<S: Sequence>(
        from cast: S,
        client: TMDbClient,
        language: Language
    ) async throws -> [CharacterCard] where S.Element == AggregrateCastMember {
        let imagesConfiguration = try await client.imagesConfiguration
        return cast.map {
            let primaryRole = $0.roles.max { lhs, rhs in
                lhs.episodeCount < rhs.episodeCount
            }?.character
                .strippingVoiceQualifier
                .nilIfEmpty
            return CharacterCard(
                id: $0.id,
                characterName: primaryRole ?? String(localized: L10n.character),
                actorName: Self.preferredActorName(
                    localizedName: $0.name,
                    originalName: $0.originalName,
                    language: language
                ),
                profileURL: imagesConfiguration.profileURL(for: $0.profilePath, idealWidth: 185)
            )
        }
    }

    private func makeSeasonCards(from seasons: [TVSeason], client: TMDbClient) async throws -> [SeasonCard] {
        let imagesConfiguration = try await client.imagesConfiguration
        return seasons
            .filter { $0.seasonNumber > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .map {
                SeasonCard(
                    id: $0.id,
                    title: $0.name,
                    subtitle: Self.seasonLabelText($0.seasonNumber),
                    posterURL: imagesConfiguration.posterURL(for: $0.posterPath, idealWidth: 300)
                )
            }
    }

    private func makeEpisodeCards(from episodes: [TVEpisode], client: TMDbClient) async throws -> [EpisodeCard] {
        let imagesConfiguration = try await client.imagesConfiguration
        return episodes.map {
            EpisodeCard(
                id: $0.id,
                title: "\($0.episodeNumber). \($0.name)",
                subtitle: $0.airDate?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: L10n.episode),
                imageURL: imagesConfiguration.stillURL(for: $0.stillPath, idealWidth: 500)
            )
        }
    }

    private static func compactCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
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

    private static func preferredActorName(localizedName: String, originalName: String?, language: Language)
        -> String
    {
        guard language == .japanese,
            let originalName,
            originalName != localizedName,
            originalName.containsJapaneseScript
        else {
            return localizedName
        }
        return originalName
    }

    private static func localizedGenreNames(_ genres: [Genre]?, language: Language) -> [String] {
        (genres ?? []).map { genre in
            localizedGenreName(for: genre, language: language)
        }
    }

    private static func localizedGenreName(for genre: Genre, language: Language) -> String {
        let localized = switch language {
        case .english:
            englishGenreNames[genre.id]
        case .japanese:
            japaneseGenreNames[genre.id]
        case .chinese:
            chineseGenreNames[genre.id]
        }

        return localized ?? genre.name
    }

    private static let englishGenreNames: [Int: String] = [
        12: "Adventure",
        14: "Fantasy",
        16: "Animation",
        18: "Drama",
        27: "Horror",
        28: "Action",
        35: "Comedy",
        36: "History",
        37: "Western",
        53: "Thriller",
        80: "Crime",
        99: "Documentary",
        878: "Science Fiction",
        9648: "Mystery",
        10402: "Music",
        10749: "Romance",
        10751: "Family",
        10752: "War",
        10759: "Action & Adventure",
        10762: "Kids",
        10763: "News",
        10764: "Reality",
        10765: "Sci-Fi & Fantasy",
        10766: "Soap",
        10767: "Talk",
        10768: "War & Politics",
        10770: "TV Movie",
    ]

    private static let japaneseGenreNames: [Int: String] = [
        12: "アドベンチャー",
        14: "ファンタジー",
        16: "アニメーション",
        18: "ドラマ",
        27: "ホラー",
        28: "アクション",
        35: "コメディ",
        36: "歴史",
        37: "西部劇",
        53: "スリラー",
        80: "犯罪",
        99: "ドキュメンタリー",
        878: "SF",
        9648: "ミステリー",
        10402: "音楽",
        10749: "ロマンス",
        10751: "ファミリー",
        10752: "戦争",
        10759: "アクション・アドベンチャー",
        10762: "キッズ",
        10763: "ニュース",
        10764: "リアリティ",
        10765: "SF・ファンタジー",
        10766: "ソープ",
        10767: "トーク",
        10768: "戦争・政治",
        10770: "テレビ映画",
    ]

    private static let chineseGenreNames: [Int: String] = [
        12: "冒险",
        14: "奇幻",
        16: "动画",
        18: "剧情",
        27: "恐怖",
        28: "动作",
        35: "喜剧",
        36: "历史",
        37: "西部",
        53: "惊悚",
        80: "犯罪",
        99: "纪录",
        878: "科幻",
        9648: "悬疑",
        10402: "音乐",
        10749: "爱情",
        10751: "家庭",
        10752: "战争",
        10759: "动作冒险",
        10762: "儿童",
        10763: "新闻",
        10764: "真人秀",
        10765: "科幻奇幻",
        10766: "肥皂剧",
        10767: "脱口秀",
        10768: "战争政治",
        10770: "电视电影",
    ]
}

private struct DetailStatCard: View {
    let card: EntryDetailModel.StatCard

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
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
        .padding(16)
        .glassPanel(cornerRadius: 24)
    }
}

private struct CharacterCardView: View {
    let card: EntryDetailModel.CharacterCard

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
        .glassPanel(cornerRadius: 24)
    }
}

private struct SeasonCardView: View {
    let card: EntryDetailModel.SeasonCard
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let posterURL = card.posterURL {
                    KFImageView(url: posterURL, targetWidth: 320, diskCacheExpiration: .longTerm)
                        .scaledToFill()
                        .frame(width: 198, height: 112)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(accentColor.opacity(0.18))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(accentColor)
                        }
                }
            }
            .frame(width: 198, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(card.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 198, alignment: .leading)
        .padding(12)
        .glassPanel(cornerRadius: 24)
    }
}

private struct EpisodeRowView: View {
    let card: EntryDetailModel.EpisodeCard

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let imageURL = card.imageURL {
                    KFImageView(url: imageURL, targetWidth: 500, diskCacheExpiration: .longTerm)
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
        .glassPanel(cornerRadius: 22)
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat, padding: CGFloat = 0, tint: Color = .white.opacity(0.05))
        -> some View
    {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var strippingVoiceQualifier: String {
        let voiceMarkerPattern = #"(?i:voice|voiced\s+by|cv|c\.?\s*v\.?)|声優|声の出演|声|吹替え|吹替|吹き替え|ボイス"#
        let patterns = [
            #"\s*[\(\（][^)\）]*(?:__VOICE_MARKERS__)[^)\）]*[\)\）]\s*$"#,
            #"\s*[\[\［][^\]\］]*(?:__VOICE_MARKERS__)[^\]\］]*[\]\］]\s*$"#,
        ].map {
            $0.replacingOccurrences(of: "__VOICE_MARKERS__", with: voiceMarkerPattern)
        }

        var value = self

        while true {
            let stripped = patterns.reduce(value) { partialResult, pattern in
                partialResult.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .regularExpression
                )
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard stripped != value else {
                return stripped
            }
            value = stripped
        }
    }

    var containsJapaneseScript: Bool {
        unicodeScalars.contains {
            switch $0.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }
    }
}

private struct EntryDetailPreviewHost: View {
    @State private var showDetail = false
    @State private var previewStore = LibraryStore(dataProvider: .forPreview)

    var body: some View {
        NavigationStack {
            VStack {
                Button(String(localized: L10n.showDetail)) {
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

private enum L10n {
    static let done: LocalizedStringResource = "Done"
    static let showDetail: LocalizedStringResource = "Show Detail"
    static let overview: LocalizedStringResource = "Overview"
    static let seasons: LocalizedStringResource = "Seasons"
    static let episodes: LocalizedStringResource = "Episodes"
    static let characters: LocalizedStringResource = "Characters"
    static let cast: LocalizedStringResource = "Cast"
    static let character: LocalizedStringResource = "Character"
    static let tmdb: LocalizedStringResource = "TMDb"
    static let couldNotLoadDetails: LocalizedStringResource = "Couldn't load details"
    static let noOverviewAvailable: LocalizedStringResource = "No overview available."
    static let tmdbScore: LocalizedStringResource = "TMDb Score"
    static let votes: LocalizedStringResource = "Votes"
    static let runtime: LocalizedStringResource = "Runtime"
    static let averageRuntime: LocalizedStringResource = "Avg Runtime"
    static let episode: LocalizedStringResource = "Episode"
}
