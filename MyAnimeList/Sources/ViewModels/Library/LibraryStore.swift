//
//  LibraryStore.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/22.
//

import Combine
import DataProvider
import Foundation
import SwiftData
import SwiftUI
import os

let libraryStoreLogger = Logger(subsystem: .bundleIdentifier, category: "LibraryStore")

@Observable @MainActor
class LibraryStore {
    // MARK: - Dependencies

    @ObservationIgnored let dataProvider: DataProvider
    @ObservationIgnored let repository: LibraryRepository
    @ObservationIgnored let preferences: LibraryPreferences
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - State

    private(set) var library: [AnimeEntry]
    @ObservationIgnored var infoFetcher: InfoFetcher
    var language: Language = .resolvedAnimeInfoLanguage()

    // MARK: - Filtering & Sorting State

    var filters: Set<AnimeFilter> = []
    var hideDroppedByDefault: Bool = false {
        willSet {
            preferences.saveHideDroppedByDefault(newValue)
            libraryStoreLogger.debug("Updated hide dropped by default to \(newValue)")
        }
    }
    var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus = .planToWatch {
        willSet {
            preferences.saveDefaultWatchStatus(newValue)
            libraryStoreLogger.debug("Updated default new entry watch status to \(newValue.preferenceValue)")
        }
    }
    var defaultFilters: Set<AnimeFilter> = [] {
        willSet {
            preferences.saveDefaultFilters(newValue)
            libraryStoreLogger.debug("Updated default filters to \(newValue.map(\.id).sorted())")
        }
        didSet {
            guard defaultFilters != oldValue else { return }
            applyDefaultFilters()
        }
    }
    var autoPrefetchImagesOnAddAndRestore: Bool = false {
        willSet {
            preferences.saveAutoPrefetchImagesOnAddAndRestore(newValue)
            libraryStoreLogger.debug("Updated auto prefetch images on add and restore to \(newValue)")
        }
    }
    var sortStrategy: AnimeSortStrategy = .dateStarted {
        willSet {
            preferences.saveSortStrategy(newValue)
            libraryStoreLogger.debug("Updated sort strategy to \(newValue.rawValue)")
        }
    }
    var sortReversed: Bool = true {
        willSet {
            preferences.saveSortReversed(newValue)
            libraryStoreLogger.debug("Updated sort reversed to \(newValue)")
        }
    }

    var libraryOnDisplay: [AnimeEntry] {
        filterAndSort(library)
    }

    var libraryDisplayItems: [LibraryEntryDisplayItem] {
        libraryOnDisplay.map(LibraryEntryDisplayItem.init)
    }

    init(dataProvider: DataProvider) {
        self.dataProvider = dataProvider
        self.repository = LibraryRepository(dataProvider: dataProvider)
        self.preferences = LibraryPreferences()
        self.infoFetcher = .init()
        self.library = []
        reloadPersistedPreferences()
        setupUpdateLibrary()
        setupTMDbAPIConfigurationChangeMonitor()
        try? refreshLibrary()
    }

    func reloadPersistedPreferences() {
        let snapshot = preferences.load()
        if sortStrategy != snapshot.sortStrategy {
            sortStrategy = snapshot.sortStrategy
        }
        if sortReversed != snapshot.sortReversed {
            sortReversed = snapshot.sortReversed
        }
        if hideDroppedByDefault != snapshot.hideDroppedByDefault {
            hideDroppedByDefault = snapshot.hideDroppedByDefault
        }
        if defaultNewEntryWatchStatus != snapshot.defaultWatchStatus {
            defaultNewEntryWatchStatus = snapshot.defaultWatchStatus
        }
        if defaultFilters != snapshot.defaultFilters {
            defaultFilters = snapshot.defaultFilters
        }
        if autoPrefetchImagesOnAddAndRestore != snapshot.autoPrefetchImagesOnAddAndRestore {
            autoPrefetchImagesOnAddAndRestore = snapshot.autoPrefetchImagesOnAddAndRestore
        }

        applyDefaultFilters()
    }

    // MARK: - Library Loading & Observers

    func refreshLibrary() throws {
        libraryStoreLogger.debug("[\(Date().debugDescription)] Refreshing library...")
        let entries = try repository.visibleLibraryEntries()
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
                    libraryStoreLogger.error("Error refreshing library: \(error)")
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

    // MARK: - Shared Helpers

    func existingEntry(tmdbID: Int) -> AnimeEntry? {
        repository.existingEntry(tmdbID: tmdbID)
    }

    func applyNewEntryDefaults(to entry: AnimeEntry) {
        entry.setWatchStatus(defaultNewEntryWatchStatus)
    }

    func applyDefaultFilters() {
        filters = defaultFilters
    }
}

#if DEBUG
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
