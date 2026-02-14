//
//  LibraryStore.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import Combine
import DataProvider
import Foundation
import Kingfisher
import SwiftData
import SwiftUI
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "LibraryStore")

@Observable @MainActor
class LibraryStore {
    // MARK: - Dependencies

    @ObservationIgnored private let dataProvider: DataProvider
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored let backupManager: BackupManager

    // MARK: - State

    private(set) var library: [AnimeEntry]
    @ObservationIgnored private var infoFetcher: InfoFetcher
    var language: Language = .current

    // MARK: - Filtering & Sorting State

    var filters: Set<AnimeFilter> = []
    var sortStrategy: AnimeSortStrategy = .dateStarted {
        willSet {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: .librarySortStrategy)
            logger.debug("Updated sort strategy to \(newValue.rawValue)")
        }
    }
    var sortReversed: Bool = false

    var libraryOnDisplay: [AnimeEntry] {
        filterAndSort(library)
    }

    init(dataProvider: DataProvider) {
        self.dataProvider = dataProvider
        self.backupManager = BackupManager(dataProvider: dataProvider)
        self.library = []
        self.infoFetcher = .init()
        if let sortStrategyRawValue = UserDefaults.standard.string(forKey: .librarySortStrategy),
            let strategy = AnimeSortStrategy(rawValue: sortStrategyRawValue)
        {
            self.sortStrategy = strategy
        }
        setupUpdateLibrary()
        setupTMDbAPIConfigurationChangeMonitor()
        try? refreshLibrary()
    }

    // MARK: - Library Loading & Observers

    func refreshLibrary() throws {
        logger.debug("[\(Date().debugDescription)] Refreshing library...")
        let entries = try dataProvider.getAllModels(ofType: AnimeEntry.self, predicate: #Predicate { $0.onDisplay })
        withAnimation {
            library = entries
        }
    }

    func setupUpdateLibrary() {
        NotificationCenter.default
            .publisher(for: ModelContext.didSave)
            .sink { [weak self] _ in
                do {
                    try self?.refreshLibrary()
                } catch {
                    logger.error("Error refreshing library: \(error)")
                }
            }
            .store(in: &cancellables)
    }

    func setupTMDbAPIConfigurationChangeMonitor() {
        NotificationCenter.default
            .publisher(for: .tmdbAPIConfigurationDidChange)
            .sink { [weak self] _ in
                self?.infoFetcher = .init()
            }
            .store(in: &cancellables)
    }

    // MARK: - Entry Creation

    @discardableResult
    func createNewEntry(
        tmdbID id: Int,
        type: AnimeType
    ) async throws -> PersistentIdentifier? {
        // No duplicate entries
        guard library.map(\.tmdbID).contains(id) == false else {
            library.entryWithTMDbID(id)?.onDisplay = true
            logger.warning(
                "Entry with id \(id) already exists. Setting `onDisplay` to `true` and returning..."
            )
            return nil
        }
        logger.debug("Creating new entry with id: \(id), type: \(type)...")
        let info = try await infoFetcher.fetchInfoFromTMDB(
            entryType: type,
            tmdbID: id,
            language: language)
        let entry = AnimeEntry(fromInfo: info)
        if let parentSeriesID = entry.parentSeriesID {
            if let parentSeriesEntry = library.first(where: { $0.tmdbID == parentSeriesID }) {
                entry.parentSeriesEntry = parentSeriesEntry
            } else {
                let parentSeriesEntry =
                    try await AnimeEntry
                    .generateParentSeriesEntryForSeason(
                        parentSeriesID: parentSeriesID,
                        fetcher: infoFetcher,
                        infoLanguage: language)
                entry.parentSeriesEntry = parentSeriesEntry
            }
        }
        return try dataProvider.dataHandler.newEntry(entry)
    }

    /// Creates a new `AnimeEntry` from a TMDB ID and adds it to the library.
    ///
    /// Does nothing if an entry with the same TMDB ID already exist.
    ///
    /// - Parameters:
    ///   - id: The TMDB ID of the anime to add.
    ///   - type: The type of the anime (e.g., `.movie`).
    ///
    /// - Returns: `true` if no error occurred; otherwise `false`.
    func newEntry(tmdbID id: Int, type: AnimeType) async -> Bool {
        do {
            try await createNewEntry(tmdbID: id, type: type)
            return true
        } catch {
            logger.error("Error creating new entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    /// Creates new `AnimeEntry` instances from search results and adds them to the library.
    /// - Returns: `true` if no error occurred; otherwise `false`.
    func newEntryFromSearchResults<Sources: Collection<SearchResult>>(_ results: Sources) async
        -> Bool
    {
        do {
            for result in results {
                try await createNewEntry(tmdbID: result.tmdbID, type: result.type)
            }
            return true
        } catch {
            logger.error("Error creating new entries from search results: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
        }
    }

    /// Creates new `AnimeEntry` instances from a `BasicInfo` and adds it to the library.
    func newEntryFromBasicInfo(_ info: BasicInfo) {
        do {
            try dataProvider.dataHandler.newEntry(.init(fromInfo: info))
        } catch {
            logger.error("Error creating new entry from BasicInfo: \(error)")
        }
    }

    // MARK: - Library Mutations

    func deleteEntry(_ entry: AnimeEntry) {
        do {
            try dataProvider.dataHandler.deleteEntry(entry)
        } catch {
            logger.error("Failed to delete entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    func clearLibrary() {
        do {
            try dataProvider.dataHandler.deleteAllEntries()
        } catch {
            logger.error("Error clearing library: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Info Refresh & Prefetch

    func chunkedLibraryEntries(chunkSize: Int) -> [ArraySlice<AnimeEntry>] {
        var chunks: [ArraySlice<AnimeEntry>] = []
        var currentIndex = library.startIndex

        while currentIndex < library.endIndex {
            let endIndex =
                library.index(
                    currentIndex,
                    offsetBy: chunkSize,
                    limitedBy: library.endIndex) ?? library.endIndex
            chunks.append(library[currentIndex..<endIndex])
            currentIndex = endIndex
        }

        return chunks
    }

    /// Fetches the latest infos from tmdb for all entries and update the entries.
    func refreshInfos() {
        Task {
            ToastCenter.global.progressState =
                .progress(
                    current: 0,
                    total: library.count,
                    messageResource: "Fetching Info: 0 / \(library.count)")

            do {
                var fetchedInfos: [Int: BasicInfo] = [:]
                let totalCount = library.count
                for chunk in chunkedLibraryEntries(chunkSize: 8) {
                    let chunkInfos = try await latestInfoForEntries(
                        entries: chunk,
                        updateProgress: { current, _ in
                            let messageResource: LocalizedStringResource =
                                "Fetching Info: \(fetchedInfos.count + current) / \(totalCount)"
                            ToastCenter.global.progressState =
                                .progress(
                                    current: fetchedInfos.count + current,
                                    total: totalCount,
                                    messageResource: messageResource)
                        })
                    for (id, info) in chunkInfos {
                        fetchedInfos[id] = info
                    }
                }
                ToastCenter.global.progressState = nil

                ToastCenter.global.loadingMessage = .message("Organizing Library...")
                for (id, info) in fetchedInfos {
                    if let entry = library.entryWithTMDbID(id) {
                        entry.update(from: info)
                        try await resolveParentSeriesEntry(for: entry)
                    }
                }
                ToastCenter.global.loadingMessage = nil
                ToastCenter.global.completionState = .completed(
                    "Refreshed infos for \(fetchedInfos.count) entries.")
            } catch {
                logger.error("Error refreshing infos: \(error)")
                ToastCenter.global.completionState = .failed(message: error.localizedDescription)
                return
            }
            prefetchAllImages()
        }
    }

    /// Fetches the latest infos from tmdb for the given entries.
    ///
    /// - Parameters:
    ///   - entries: The entries to fetch latest infos for.
    ///   - updateProgress: A (current, total) closure called when progress is updated.
    ///
    /// - Returns: An array of (tmdbID, BasicInfo) tuples.
    /// - Throws: An error if fetching fails.
    func latestInfoForEntries<C: Collection<AnimeEntry>>(
        entries: C,
        updateProgress: @escaping (Int, Int) -> Void
    ) async throws -> [(Int, BasicInfo)] {
        try await withThrowingTaskGroup(
            of: (Int, BasicInfo).self
        ) { group in
            var fetchedInfos: [(Int, BasicInfo)] = []

            for entry in entries {
                let tmdbID = entry.tmdbID
                let type = entry.type
                let persistentID = entry.id
                let originalPosterURL = entry.posterURL
                let usingCustomPoster = entry.usingCustomPoster
                group.addTask {
                    try await self.fetchLatestInfo(
                        tmdbID: tmdbID,
                        entryType: type,
                        persistentID: persistentID,
                        originalPosterURL: originalPosterURL,
                        usingCustomPoster: usingCustomPoster)
                }
            }

            for try await result in group {
                fetchedInfos.append(result)
                updateProgress(fetchedInfos.count, entries.count)
            }

            return fetchedInfos
        }
    }

    func fetchLatestInfo(
        tmdbID: Int,
        entryType: AnimeType,
        persistentID: PersistentIdentifier,
        originalPosterURL: URL?,
        usingCustomPoster: Bool
    ) async throws -> (Int, BasicInfo) {
        var info = try await self.infoFetcher.fetchInfoFromTMDB(
            entryType: entryType,
            tmdbID: tmdbID,
            language: language)
        if usingCustomPoster {
            // Preserve the original poster URL if using a custom poster
            info.posterURL = originalPosterURL
        }
        return (tmdbID, info)
    }

    func resolveParentSeriesEntry(for entry: AnimeEntry) async throws {
        if let parentSeriesID = entry.parentSeriesID {
            if let parentSeriesEntry = library.entryWithTMDbID(parentSeriesID) {
                entry.parentSeriesEntry = parentSeriesEntry
            } else {
                if let parentSeriesID = entry.parentSeriesID {
                    let parentSeriesEntry =
                        try await AnimeEntry
                        .generateParentSeriesEntryForSeason(
                            parentSeriesID: parentSeriesID,
                            fetcher: infoFetcher,
                            infoLanguage: language)
                    entry.parentSeriesEntry = parentSeriesEntry
                }
            }
        }
    }

    func prefetchAllImages() {
        let urls = library.compactMap { $0.posterURL }
        ToastCenter.global.progressState =
            .progress(
                current: 0,
                total: urls.count,
                messageResource: "Fetching Images: 0 / \(urls.count)")
        let prefetcher = ImagePrefetcher(
            urls: urls,
            progressBlock: { skipped, failed, completed in
                let total = urls.count
                let current = skipped.count + failed.count + completed.count
                ToastCenter.global.progressState =
                    .progress(
                        current: current,
                        total: total,
                        messageResource: "Fetching Images: \(current) / \(total)")
            },
            completionHandler: { skipped, failed, completed in
                var state: ToastCenter.CompletedWithMessage.State = .completed
                let messageResourceString =
                    "Fetched: \(skipped.count + completed.count), failed: \(failed.count)"
                let messageResource = LocalizedStringResource(
                    "Fetched: \(skipped.count + completed.count), failed: \(failed.count)")
                if failed.isEmpty {
                    state = .completed
                } else if completed.isEmpty && skipped.isEmpty {
                    state = .failed
                } else {
                    state = .partialComplete
                }
                ToastCenter.global.progressState = nil
                ToastCenter.global.completionState = .init(
                    state: state,
                    messageResource: messageResource)
                logger.info("Prefetched images: \(messageResourceString)")
            })
        prefetcher.start()
    }

    // MARK: - Conversion helpers

    /// Convert a season entry back to its series entry
    /// while preserving user metadata and custom posters.
    ///
    /// Strategy: materialize (or reuse) the parent series entry as visible,
    /// apply the user's metadata, then remove the season entry.
    ///
    func convertSeasonToSeries(_ entry: AnimeEntry, language: Language) async throws {
        guard case .season(_, let parentSeriesID) = entry.type else { return }
        let seasonTMDbID = entry.tmdbID
        logger.info("Converting season \(seasonTMDbID, privacy: .public) to series \(parentSeriesID, privacy: .public)")

        let userInfo = entry.userInfo
        let originalPosterURL = entry.posterURL

        // Resolve or fetch the parent series entry using shared helpers and in-memory library
        let parentEntry: AnimeEntry
        if let existingParent = entry.parentSeriesEntry {
            parentEntry = existingParent
            parentEntry.onDisplay = true
        } else {
            let parentInfo = try await infoFetcher.tvSeriesInfo(tmdbID: parentSeriesID, language: language)
            parentEntry = AnimeEntry(fromInfo: parentInfo)
            parentEntry.onDisplay = true
            try dataProvider.dataHandler.newEntry(parentEntry)
        }

        // Apply user metadata to the parent series entry
        parentEntry.updateUserInfo(from: userInfo)
        if userInfo.usingCustomPoster {
            parentEntry.posterURL = originalPosterURL
        }

        // Remove the original season entry
        try dataProvider.dataHandler.deleteEntry(entry)

        logger.info("Converted season \(seasonTMDbID, privacy: .public) to series \(parentSeriesID, privacy: .public)")
    }

    /// Convert a series entry to a specific season
    /// while preserving user metadata and custom posters.
    ///
    /// Strategy: delete the original series entry, create a hidden parent series entry,
    /// and add a new season entry with carried user metadata using shared helpers.
    ///
    func convertSeriesToSeason(
        _ entry: AnimeEntry,
        seasonNumber: Int,
        language: Language
    ) async throws {
        let parentSeriesID = entry.tmdbID
        logger.info("Converting series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")

        let userInfo = entry.userInfo
        let originalPosterURL = entry.posterURL

        // Fetch infos before deleting the original entry
        let parentInfo = try await infoFetcher.tvSeriesInfo(tmdbID: parentSeriesID, language: language)
        var seasonInfo = try await infoFetcher.tvSeasonInfo(
            seasonNumber: seasonNumber,
            parentSeriesID: parentSeriesID,
            language: language)

        // Remove the original series entry from the library
        try dataProvider.dataHandler.deleteEntry(entry)

        if userInfo.usingCustomPoster {
            seasonInfo.posterURL = originalPosterURL
        }

        // Hidden parent series entry
        let parentEntry = AnimeEntry(fromInfo: parentInfo)
        parentEntry.onDisplay = false

        // New season entry with user metadata
        let seasonEntry = AnimeEntry(fromInfo: seasonInfo)
        seasonEntry.parentSeriesEntry = parentEntry
        seasonEntry.updateUserInfo(from: userInfo)
        if userInfo.usingCustomPoster {
            seasonEntry.posterURL = originalPosterURL
        }

        try dataProvider.dataHandler.newEntry(parentEntry)
        try dataProvider.dataHandler.newEntry(seasonEntry)

        logger.info("Converted series \(parentSeriesID, privacy: .public) to season \(seasonNumber, privacy: .public)")
    }

    // MARK: - Filtering & Sorting

    func filterAndSort(_ entries: [AnimeEntry]) -> [AnimeEntry] {
        let sorted: [AnimeEntry]
        if !sortReversed {
            sorted =
                entries
                .sorted(by: sortStrategy.compare)
        } else {
            sorted =
                entries
                .sorted(by: sortStrategy.compare)
                .reversed()
        }
        guard filters.isEmpty else {
            return sorted.filter { entry in
                filters.contains { filter in
                    filter.evaluate(entry)
                }
            }
        }
        return sorted
    }

    // MARK: - Filters

    struct AnimeFilter: Sendable, CaseIterable, Equatable, Hashable {
        static let favorited = AnimeFilter(id: "Favorited", name: "Favorited") { $0.favorite }
        static let watched = AnimeFilter(id: "Watched", name: "Watched") {
            $0.watchStatus == WatchedStatus.watched
        }
        static let planToWatch = AnimeFilter(id: "Plan to Watch", name: "Plan to Watch") {
            $0.watchStatus == .planToWatch
        }
        static let watching = AnimeFilter(id: "Watching", name: "Watching") {
            $0.watchStatus == .watching
        }

        private init(
            id: String, name: LocalizedStringResource,
            evaluate: @escaping @Sendable (AnimeEntry) -> Bool
        ) {
            self.id = id
            self.name = name
            self.evaluate = evaluate
        }

        let id: String
        let name: LocalizedStringResource
        let evaluate: @Sendable (AnimeEntry) -> Bool

        static var allCases: [LibraryStore.AnimeFilter] {
            [.favorited, .watched, .planToWatch, .watching]
        }

        static func == (lhs: LibraryStore.AnimeFilter, rhs: LibraryStore.AnimeFilter) -> Bool {
            lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    // MARK: - Sorting

    enum AnimeSortStrategy: String,
        CaseIterable,
        CustomLocalizedStringResourceConvertible,
        Codable
    {
        case dateSaved, dateStarted, dateFinished, dateOnAir

        func compare(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
            switch self {
            case .dateSaved:
                return lhs.dateSaved < rhs.dateSaved
            case .dateStarted:
                return lhs.dateStarted ?? .distantFuture < rhs.dateStarted ?? .distantFuture
            case .dateFinished:
                return lhs.dateFinished ?? .distantFuture < rhs.dateFinished ?? .distantFuture
            case .dateOnAir:
                return lhs.onAirDate ?? .distantFuture < rhs.onAirDate ?? .distantFuture
            }
        }

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .dateFinished: "Date Finished"
            case .dateSaved: "Date Saved"
            case .dateStarted: "Date Started"
            case .dateOnAir: "Date On Air"
            }
        }
    }
}

#if DEBUG
// This is where we place debug-specific code.
extension LibraryStore {
    /// Mock delete, doesn't really touch anything in the persisted data model.
    ///
    /// Restores after 1.5 seconds.
    func mockDeleteEntry(_ entry: AnimeEntry) {
        if let index = library.firstIndex(where: { $0.id == entry.id }) {
            library.remove(at: index)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.library.insert(entry, at: index)
            }
        }
    }
}
#endif
