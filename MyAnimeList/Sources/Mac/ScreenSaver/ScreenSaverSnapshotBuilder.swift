//
//  ScreenSaverSnapshotBuilder.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import DataProvider
    import Foundation
    import ScreenSaverKit

    struct ScreenSaverSnapshotDraft: Equatable {
        struct Entry: Equatable {
            let id: String
            let title: String?
            let season: String?
            let year: String?
            let airDate: Date?
            let watchStartDate: Date?
            let watchEndDate: Date?
            let dateLocaleIdentifier: String
            let genres: [String]?
            let status: String?
            let score: String?
            let watchStatus: String?
            let userScore: String?
            let overview: String?
            let poster: TMDbImage?
            let previewPoster: TMDbImage?
            let backdrop: URL?
            let previewBackdrop: TMDbImage?
            let logo: TMDbImage?

            /// This entry's text with the given artwork, as the saver reads it.
            func manifestEntry(
                poster: String, posterPixelSize: ScreenSaverManifest.Entry.PixelSize, backdrop: String? = nil,
                logo: String? = nil
            ) -> ScreenSaverManifest.Entry {
                .init(
                    id: id, title: title, season: season, year: year, airDate: airDate,
                    watchStartDate: watchStartDate, watchEndDate: watchEndDate,
                    dateLocaleIdentifier: dateLocaleIdentifier,
                    genres: genres, status: status, score: score, watchStatus: watchStatus, userScore: userScore,
                    overview: overview, poster: poster, posterPixelSize: posterPixelSize, backdrop: backdrop, logo: logo
                )
            }
        }

        let settings: ScreenSaverManifest.Settings
        let entries: [Entry]
    }

    @MainActor
    enum ScreenSaverSnapshotBuilder {
        static func build(
            from store: LibraryStore,
            settings: ScreenSaverSettings,
            language: Language,
            scoringEnabled: Bool = true
        ) -> ScreenSaverSnapshotDraft {
            // Deleting a category leaves its memberships on entries, so a deleted category shows nothing.
            if case .category(let id) = settings.scope, !store.categories.contains(where: { $0.id == id }) {
                return .init(settings: settings.manifestSettings, entries: [])
            }
            let entries = store.library.lazy
                .filter(settings.scope.includes)
                .map { makeEntry($0, settings: settings, language: language, scoringEnabled: scoringEnabled) }
                .sorted { $0.id < $1.id }
            return .init(settings: settings.manifestSettings, entries: entries)
        }

        /// TMDb's Animation genre is true of nearly every entry, so it adds nothing on screen.
        private static let animationGenreID = 16

        private static func makeEntry(
            _ entry: AnimeEntry,
            settings: ScreenSaverSettings,
            language: Language,
            scoringEnabled: Bool
        ) -> ScreenSaverSnapshotDraft.Entry {
            // Every text detail is always included, so turning a detail on or off needs no new artwork.
            let locale = Locale(identifier: language.rawValueWithRegion)
            let airDate = entry.onAirDate
            let season: String? =
                if case .season(let number, _) = entry.type {
                    EntryDetailViewModel.seasonLabelText(number, locale: locale)
                } else {
                    nil
                }
            let seriesDetail = entry.parentSeriesEntry?.detail ?? entry.detail
            let genreIDs = (entry.detail?.genreIDs ?? seriesDetail?.genreIDs ?? []).filter { $0 != animationGenreID }
            let genres = Array(EntryDetailViewModel.localizedGenreNames(genreIDs, language: language).prefix(3))
            let status =
                entry.type == .movie
                ? nil : seriesDetail?.status.map { EntryDetailViewModel.localizedStatus($0, language: language) }

            var watchStatus = entry.watchStatus.localizedStringResource
            watchStatus.locale = locale

            let isBackdrop = settings.layout == .backdrop
            let backdrop =
                isBackdrop ? TMDbImageURLResolver.current.originalURL(for: entry.backdropPath, role: .backdrop) : nil
            return .init(
                id: entry.libraryIdentity.rawID,
                title: entry.displayName,
                season: season,
                year: airDate?.formatted(.dateTime.year().locale(locale)),
                airDate: airDate,
                watchStartDate: entry.dateStarted,
                watchEndDate: entry.dateFinished,
                dateLocaleIdentifier: locale.identifier,
                genres: genres.isEmpty ? nil : genres,
                status: status,
                score: (entry.detail?.voteAverage).flatMap { $0 > 0 ? "TMDb " + String(format: "%.1f", $0) : nil },
                watchStatus: String(localized: watchStatus),
                // Hidden along with the app's own star scores when scoring is turned off.
                userScore: scoringEnabled
                    ? entry.entryScore.map { "★ " + $0.formatted } : nil,
                overview: (entry.detail?.overview).flatMap { $0.isEmpty ? nil : $0 } ?? entry.displayOverview,
                poster: entry.posterImage(.screenSaverPoster),
                previewPoster: entry.posterImage(.posterThumbnail),
                backdrop: backdrop,
                previewBackdrop: isBackdrop ? entry.backdropImage : nil,
                logo: isBackdrop ? entry.detail?.logoImage : nil
            )
        }
    }
#endif
