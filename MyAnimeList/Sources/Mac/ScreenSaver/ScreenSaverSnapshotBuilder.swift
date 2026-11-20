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
            let subtitle: String?
            let meta: String?
            let poster: TMDbImage?
            let previewPoster: TMDbImage?
            let backdrop: URL?
            let previewBackdrop: TMDbImage?
            let logo: TMDbImage?
        }

        let settings: ScreenSaverManifest.Settings
        let entries: [Entry]
    }

    @MainActor
    enum ScreenSaverSnapshotBuilder {
        static func build(
            from store: LibraryStore,
            settings: ScreenSaverSettings,
            language: Language
        ) -> ScreenSaverSnapshotDraft {
            let entries = store.library.lazy
                .filter(settings.scope.includes)
                .map { makeEntry($0, settings: settings, language: language) }
                .sorted { $0.id < $1.id }
            return .init(settings: settings.manifestSettings, entries: entries)
        }

        private static func makeEntry(
            _ entry: AnimeEntry,
            settings: ScreenSaverSettings,
            language: Language
        ) -> ScreenSaverSnapshotDraft.Entry {
            let locale = Locale(identifier: language.rawValueWithRegion)
            let subtitle: String?
            if settings.showsTitles, case .season(let number, _) = entry.type {
                subtitle = EntryDetailViewModel.seasonLabelText(number, locale: locale)
            } else {
                subtitle = nil
            }

            let isHero = settings.layout == .heroStill
            let backdrop =
                isHero ? TMDbImageURLResolver.current.originalURL(for: entry.backdropPath, role: .backdrop) : nil
            let detail = entry.detail
            return .init(
                id: entry.libraryIdentity.rawID,
                title: settings.showsTitles ? entry.displayName : nil,
                subtitle: subtitle,
                meta: isHero ? heroMetadata(for: entry, language: language, locale: locale) : nil,
                poster: entry.posterImage(.screenSaverPoster),
                previewPoster: entry.posterImage(.posterThumbnail),
                backdrop: backdrop,
                previewBackdrop: isHero ? entry.backdropImage : nil,
                logo: isHero ? detail?.logoImage : nil
            )
        }

        private static func heroMetadata(for entry: AnimeEntry, language: Language, locale: Locale) -> String? {
            let year = entry.onAirDate?.formatted(.dateTime.year().locale(locale))
            let seriesDetail = entry.parentSeriesEntry?.detail ?? entry.detail
            let genreIDs = entry.detail?.genreIDs ?? seriesDetail?.genreIDs ?? []
            let genres = EntryDetailViewModel.localizedGenreNames(genreIDs, language: language).prefix(3)
            let status =
                entry.type == .movie
                ? nil
                : seriesDetail?.status.map {
                    EntryDetailViewModel.localizedStatus($0, language: language)
                }
            let parts = [year].compactMap(\.self) + genres + [status].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
#endif
