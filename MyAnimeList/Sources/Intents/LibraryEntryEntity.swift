//
//  LibraryEntryEntity.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents
import CoreSpotlight
import DataProvider
import Foundation
import Kingfisher

/// A value snapshot of one visible library entry for Shortcuts and Spotlight.
///
/// The ID is `LibraryEntryIdentity.rawID`, which survives restore, reinstall, and sync,
/// so saved shortcuts and indexed items keep pointing at the same entry.
struct LibraryEntryEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Library Entry",
        numericFormat: "\(placeholder: .int) library entries"
    )

    static let defaultQuery = LibraryEntryQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Watch Status")
    var status: WatchStatusAppEnum

    @Property(title: "Is Favorite")
    var isFavorite: Bool

    @Property(title: "Score")
    var score: Int?

    @Property(title: "Date Saved")
    var dateSaved: Date

    @Property(title: "Entry Type")
    var kind: LibraryEntryKindAppEnum

    @Property(title: "Season")
    var seasonNumber: Int?

    @Property(title: "Episodes Watched")
    var watchedEpisodes: Int?

    /// For example "Season 1 · Watching · EP12".
    let subtitle: String
    let alternateNames: [String]
    let overview: String?
    private let posterPath: String?

    @MainActor
    init(entry: AnimeEntry) {
        let snapshot = LibraryEntrySnapshot(entry: entry)
        id = entry.libraryIdentity.rawID
        subtitle = Self.subtitle(for: entry, snapshot: snapshot)
        alternateNames = Self.alternateNames(for: entry)
        overview = entry.displayOverview
        posterPath = entry.selectedPosterPath
        name = entry.displayName
        status = WatchStatusAppEnum(entry.watchStatus)
        isFavorite = entry.favorite
        score = entry.score
        dateSaved = entry.dateSaved
        kind = LibraryEntryKindAppEnum(entry.type)
        seasonNumber = entry.type.seasonNumber
        watchedEpisodes =
            entry.type == .movie ? nil : entry.latestEpisodeProgressSummary?.watchedThroughEpisode ?? 0
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: Self.posterImage(posterPath: posterPath)
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        // The default set fills in only the title, and Spotlight shows `contentDescription`
        // as the subtitle. iOS Spotlight currently matches only the title and display name;
        // translated titles also go in `keywords` so they match if that changes.
        let attributes = defaultAttributeSet
        attributes.displayName = name
        attributes.contentDescription = subtitle
        attributes.alternateNames = alternateNames
        attributes.keywords = alternateNames
        // Indexed for search but not shown; notes are never indexed.
        attributes.textContent = overview
        if let thumbnailData = Self.cachedPosterData(posterPath: posterPath) {
            attributes.thumbnailData = thumbnailData
        }
        return attributes
    }

    /// Changes whenever anything Spotlight shows or searches changes.
    var spotlightFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(subtitle)
        hasher.combine(alternateNames)
        hasher.combine(overview)
        hasher.combine(posterPath)
        return hasher.finalize()
    }

    // MARK: - Snapshot helpers

    @MainActor
    private static func subtitle(for entry: AnimeEntry, snapshot: LibraryEntrySnapshot) -> String {
        let kindText: String =
            switch entry.type {
            case .movie: String(localized: "Movie")
            case .series: String(localized: "TV Series")
            case .season: snapshot.secondaryMetadata ?? String(localized: "Season")
            }
        return [
            kindText,
            String(localized: entry.watchStatus.localizedStringResource),
            snapshot.episodeProgressLabel,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    @MainActor
    private static func alternateNames(for entry: AnimeEntry) -> [String] {
        var names: [String] = []
        if entry.parentSeriesEntry != nil {
            names.append(entry.name)
        }
        names += entry.nameTranslations.values
        names += entry.parentSeriesEntry?.nameTranslations.values.map(\.self) ?? []
        var seen = Set<String>([entry.displayName])
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }.sorted()
    }

    // MARK: - Poster

    /// Poster widths the library prefetches, smallest first.
    private static let cachedPosterDisplayTypes: [TMDbPosterDisplayType] = [.list, .grid]

    private static func posterImage(posterPath: String?) -> DisplayRepresentation.Image? {
        if let data = cachedPosterData(posterPath: posterPath) {
            return DisplayRepresentation.Image(data: data)
        }
        guard
            let url = TMDbImageURLResolver.current.url(
                for: posterPath,
                role: .poster,
                idealWidth: TMDbPosterDisplayType.list.idealWidth
            )
        else { return nil }
        return DisplayRepresentation.Image(url: url)
    }

    /// Reads a downsampled poster the library already cached, so Shortcuts and Spotlight
    /// show posters without a network request.
    private static func cachedPosterData(posterPath: String?) -> Data? {
        for displayType in cachedPosterDisplayTypes {
            guard
                let url = TMDbImageURLResolver.current.url(
                    for: posterPath,
                    role: .poster,
                    idealWidth: displayType.idealWidth
                ),
                let processor = LibraryImageProcessorFactory.processor(
                    for: url,
                    targetSize: PosterImageSize.targetSize(width: CGFloat(displayType.idealWidth))
                ),
                let fileURL = KingfisherManager.shared.cache.cacheFileURLIfOnDisk(
                    forKey: url.cacheKey,
                    processorIdentifier: processor.identifier
                ),
                let data = try? Data(contentsOf: fileURL)
            else { continue }
            return data
        }
        return nil
    }
}
