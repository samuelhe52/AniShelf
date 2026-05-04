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
    var language: Language = .resolvedAnimeInfoLanguage()

    // MARK: - Filtering & Sorting State

    var filters: Set<AnimeFilter> = []
    var hideDroppedByDefault: Bool = false {
        willSet {
            UserDefaults.standard.setValue(newValue, forKey: .libraryHideDroppedByDefault)
            logger.debug("Updated hide dropped by default to \(newValue)")
        }
    }
    var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus = .planToWatch {
        willSet {
            UserDefaults.standard.setValue(newValue.preferenceValue, forKey: .libraryDefaultWatchStatus)
            logger.debug("Updated default new entry watch status to \(newValue.preferenceValue)")
        }
    }
    var defaultFilters: Set<AnimeFilter> = [] {
        willSet {
            let filterIDs = newValue.map(\.id).sorted()
            UserDefaults.standard.setValue(filterIDs, forKey: .libraryDefaultFilters)
            logger.debug("Updated default filters to \(filterIDs)")
        }
        didSet {
            guard defaultFilters != oldValue else { return }
            applyDefaultFilters()
        }
    }
    var autoPrefetchImagesOnAddAndRestore: Bool = false {
        willSet {
            UserDefaults.standard.setValue(
                newValue,
                forKey: .libraryAutoPrefetchImagesOnAddAndRestore
            )
            logger.debug("Updated auto prefetch images on add and restore to \(newValue)")
        }
    }
    var sortStrategy: AnimeSortStrategy = .dateStarted {
        willSet {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: .librarySortStrategy)
            logger.debug("Updated sort strategy to \(newValue.rawValue)")
        }
    }
    var sortReversed: Bool = true {
        willSet {
            UserDefaults.standard.setValue(newValue, forKey: .librarySortReversed)
            logger.debug("Updated sort reversed to \(newValue)")
        }
    }

    var libraryOnDisplay: [AnimeEntry] {
        filterAndSort(library)
    }

    init(dataProvider: DataProvider) {
        self.dataProvider = dataProvider
        self.backupManager = BackupManager(dataProvider: dataProvider)
        self.library = []
        self.infoFetcher = .init()
        reloadPersistedPreferences()
        setupUpdateLibrary()
        setupTMDbAPIConfigurationChangeMonitor()
        try? refreshLibrary()
    }

    func reloadPersistedPreferences() {
        let defaults = UserDefaults.standard

        let resolvedSortStrategy =
            defaults
            .string(forKey: .librarySortStrategy)
            .flatMap(AnimeSortStrategy.init(rawValue:))
            ?? .dateStarted
        if sortStrategy != resolvedSortStrategy {
            sortStrategy = resolvedSortStrategy
        }

        let resolvedSortReversed =
            if defaults.object(forKey: .librarySortReversed) != nil {
                defaults.bool(forKey: .librarySortReversed)
            } else {
                true
            }
        if sortReversed != resolvedSortReversed {
            sortReversed = resolvedSortReversed
        }

        let resolvedHideDroppedByDefault =
            if defaults.object(forKey: .libraryHideDroppedByDefault) != nil {
                defaults.bool(forKey: .libraryHideDroppedByDefault)
            } else {
                false
            }
        if hideDroppedByDefault != resolvedHideDroppedByDefault {
            hideDroppedByDefault = resolvedHideDroppedByDefault
        }

        let resolvedDefaultWatchStatus =
            defaults
            .string(forKey: .libraryDefaultWatchStatus)
            .flatMap(AnimeEntry.WatchStatus.init(preferenceValue:))
            ?? .planToWatch
        if defaultNewEntryWatchStatus != resolvedDefaultWatchStatus {
            defaultNewEntryWatchStatus = resolvedDefaultWatchStatus
        }

        let resolvedDefaultFilters: Set<AnimeFilter>
        if let storedFilterIDs = defaults.array(forKey: .libraryDefaultFilters) as? [String] {
            resolvedDefaultFilters = Set(storedFilterIDs.compactMap(AnimeFilter.init(preferenceID:)))
        } else if let legacyPreset = defaults.string(forKey: .libraryDefaultFilterPreset) {
            resolvedDefaultFilters = legacyDefaultFilters(for: legacyPreset)
        } else {
            resolvedDefaultFilters = []
        }
        if defaultFilters != resolvedDefaultFilters {
            defaultFilters = resolvedDefaultFilters
        }

        let resolvedAutoPrefetchImagesOnAddAndRestore =
            if defaults.object(forKey: .libraryAutoPrefetchImagesOnAddAndRestore) != nil {
                defaults.bool(forKey: .libraryAutoPrefetchImagesOnAddAndRestore)
            } else {
                false
            }
        if autoPrefetchImagesOnAddAndRestore != resolvedAutoPrefetchImagesOnAddAndRestore {
            autoPrefetchImagesOnAddAndRestore = resolvedAutoPrefetchImagesOnAddAndRestore
        }

        applyDefaultFilters()
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
    ) async throws -> AnimeEntry? {
        // No duplicate entries
        guard library.map(\.tmdbID).contains(id) == false else {
            library.entryWithTMDbID(id)?.onDisplay = true
            logger.warning(
                "Entry with id \(id) already exists. Setting `onDisplay` to `true` and returning..."
            )
            return nil
        }
        logger.debug("Creating new entry with id: \(id), type: \(type)...")
        async let info = infoFetcher.fetchInfoFromTMDB(
            entryType: type,
            tmdbID: id,
            language: language)
        async let detail = infoFetcher.detailInfo(
            entryType: type,
            tmdbID: id,
            language: language
        )
        let entry = AnimeEntry(fromInfo: try await info)
        applyNewEntryDefaults(to: entry)
        entry.detail = try await detail
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
        try dataProvider.dataHandler.newEntry(entry)
        return entry
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
            if let entry = try await createNewEntry(tmdbID: id, type: type) {
                prefetchImagesForDefaultBehavior([entry])
            }
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
            var createdEntries: [AnimeEntry] = []
            for result in results {
                if let entry = try await createNewEntry(tmdbID: result.tmdbID, type: result.type) {
                    createdEntries.append(entry)
                }
            }
            prefetchImagesForDefaultBehavior(createdEntries)
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
            let entry = AnimeEntry(fromInfo: info)
            applyNewEntryDefaults(to: entry)
            try dataProvider.dataHandler.newEntry(entry)
            prefetchImagesForDefaultBehavior([entry])
        } catch {
            logger.error("Error creating new entry from BasicInfo: \(error)")
        }
    }

    // MARK: - Library Mutations

    @discardableResult
    func deleteEntry(_ entry: AnimeEntry) -> Bool {
        do {
            try dataProvider.dataHandler.deleteEntry(entry)
            return true
        } catch {
            logger.error("Failed to delete entry: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
            return false
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
                var fetchedInfos: [Int: (BasicInfo, AnimeEntryDetail)] = [:]
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
                    for (id, info, detail) in chunkInfos {
                        fetchedInfos[id] = (info, detail)
                    }
                }
                ToastCenter.global.progressState = nil

                ToastCenter.global.loadingMessage = .message("Organizing Library...")
                for (id, payload) in fetchedInfos {
                    if let entry = library.entryWithTMDbID(id) {
                        entry.update(from: payload.0)
                        entry.detail = payload.1
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
    /// - Returns: An array of (tmdbID, BasicInfo, AnimeEntryDetail) tuples.
    /// - Throws: An error if fetching fails.
    func latestInfoForEntries<C: Collection<AnimeEntry>>(
        entries: C,
        updateProgress: @escaping (Int, Int) -> Void
    ) async throws -> [(Int, BasicInfo, AnimeEntryDetail)] {
        try await withThrowingTaskGroup(
            of: (Int, BasicInfo, AnimeEntryDetail).self
        ) { group in
            var fetchedInfos: [(Int, BasicInfo, AnimeEntryDetail)] = []

            for entry in entries {
                let tmdbID = entry.tmdbID
                let type = entry.type
                let originalPosterURL = entry.posterURL
                let usingCustomPoster = entry.usingCustomPoster
                group.addTask {
                    try await self.fetchLatestInfo(
                        tmdbID: tmdbID,
                        entryType: type,
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
        originalPosterURL: URL?,
        usingCustomPoster: Bool
    ) async throws -> (Int, BasicInfo, AnimeEntryDetail) {
        let payload = try await self.infoFetcher.latestInfo(
            entryType: entryType,
            tmdbID: tmdbID,
            language: language)
        var resolvedInfo = payload.0
        if usingCustomPoster {
            // Preserve the original poster URL if using a custom poster
            resolvedInfo.posterURL = originalPosterURL
        }
        return (tmdbID, resolvedInfo, payload.1)
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
        prefetchImages(for: library)
    }

    private func prefetchImagesForDefaultBehavior<C: Collection>(_ entries: C)
    where C.Element == AnimeEntry {
        guard autoPrefetchImagesOnAddAndRestore else { return }
        prefetchImages(for: entries)
    }

    private func prefetchImages<C: Collection>(for entries: C)
    where C.Element == AnimeEntry {
        let urls = Array(Set(imageURLs(for: entries)))
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

    private func imageURLs<C: Collection>(for entries: C) -> [URL]
    where C.Element == AnimeEntry {
        entries.flatMap { entry in
            [entry.posterURL, entry.detail?.heroImageURL, entry.detail?.logoImageURL].compactMap(\.self)
        }
    }

    private func applyNewEntryDefaults(to entry: AnimeEntry) {
        entry.setWatchStatus(defaultNewEntryWatchStatus)
    }

    private func applyDefaultFilters() {
        filters = defaultFilters
    }

    private func legacyDefaultFilters(for preset: String) -> Set<AnimeFilter> {
        switch preset {
        case "favorites":
            [.favorited]
        case "watched":
            [.watched]
        case "planToWatch":
            [.planToWatch]
        case "watching":
            [.watching]
        case "dropped":
            [.dropped]
        default:
            []
        }
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
            parentEntry.detail = try await infoFetcher.detailInfo(
                entryType: .series,
                tmdbID: parentSeriesID,
                language: language
            )
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
        let seasonTMDbID = entry.tmdbID

        // Fetch infos before deleting the original entry
        async let parentInfo = infoFetcher.tvSeriesInfo(tmdbID: parentSeriesID, language: language)
        async let parentDetail = infoFetcher.detailInfo(
            entryType: .series,
            tmdbID: parentSeriesID,
            language: language
        )
        async let seasonInfo = infoFetcher.tvSeasonInfo(
            seasonNumber: seasonNumber,
            parentSeriesID: parentSeriesID,
            language: language)
        async let seasonDetail = infoFetcher.detailInfo(
            entryType: .season(seasonNumber: seasonNumber, parentSeriesID: parentSeriesID),
            tmdbID: seasonTMDbID,
            language: language
        )
        let resolvedParentInfo = try await parentInfo
        var resolvedSeasonInfo = try await seasonInfo

        // Remove the original series entry from the library
        try dataProvider.dataHandler.deleteEntry(entry)

        if userInfo.usingCustomPoster {
            resolvedSeasonInfo.posterURL = originalPosterURL
        }

        // Hidden parent series entry
        let parentEntry = AnimeEntry(fromInfo: resolvedParentInfo)
        parentEntry.detail = try await parentDetail
        parentEntry.onDisplay = false

        // New season entry with user metadata
        let seasonEntry = AnimeEntry(fromInfo: resolvedSeasonInfo)
        seasonEntry.detail = try await seasonDetail
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
        let defaultDisplayEntries: [AnimeEntry]
        if hideDroppedByDefault && !filters.contains(.dropped) {
            defaultDisplayEntries = sorted.filter { $0.watchStatus != .dropped }
        } else {
            defaultDisplayEntries = sorted
        }
        guard filters.isEmpty else {
            return defaultDisplayEntries.filter { entry in
                filters.contains { filter in
                    filter.evaluate(entry)
                }
            }
        }
        return defaultDisplayEntries
    }

    // MARK: - Filters

    struct AnimeFilter: Sendable, CaseIterable, Equatable, Hashable {
        static let favorited = AnimeFilter(id: "Favorites", name: "Favorites") { $0.favorite }
        static let watched = AnimeFilter(id: "Watched", name: "Watched") {
            $0.watchStatus == WatchedStatus.watched
        }
        static let planToWatch = AnimeFilter(id: "Plan to Watch", name: "Planned") {
            $0.watchStatus == .planToWatch
        }
        static let watching = AnimeFilter(id: "Watching", name: "Watching") {
            $0.watchStatus == .watching
        }
        static let dropped = AnimeFilter(id: "Dropped", name: "Dropped") {
            $0.watchStatus == .dropped
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

        init?(preferenceID: String) {
            guard let filter = Self.allCases.first(where: { $0.id == preferenceID }) else {
                return nil
            }
            self = filter
        }

        static var allCases: [LibraryStore.AnimeFilter] {
            [.favorited, .watched, .planToWatch, .watching, .dropped]
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

extension AnimeEntry.WatchStatus {
    var preferenceValue: String {
        switch self {
        case .planToWatch:
            "planToWatch"
        case .watching:
            "watching"
        case .watched:
            "watched"
        case .dropped:
            "dropped"
        }
    }

    init?(preferenceValue: String) {
        switch preferenceValue {
        case "planToWatch":
            self = .planToWatch
        case "watching":
            self = .watching
        case "watched":
            self = .watched
        case "dropped":
            self = .dropped
        default:
            return nil
        }
    }
}
