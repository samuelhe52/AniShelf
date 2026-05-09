//
//  LibraryProfileSettingsActions.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/7.
//

import Foundation
import Kingfisher

@MainActor
final class LibraryProfileSettingsActions {
    typealias RefreshInfosHandler = @MainActor (LibraryStore, LibraryRefreshOptions) -> Void

    private let store: LibraryStore
    /// Indirection for the metadata refresh path so tests can verify routing
    /// and inject alternate presentation backends without changing the core flow.
    private let refreshInfosHandler: RefreshInfosHandler

    init(store: LibraryStore) {
        self.store = store
        self.refreshInfosHandler = Self.performRefreshInfos
    }

    init(store: LibraryStore, refreshInfosHandler: @escaping RefreshInfosHandler) {
        self.store = store
        self.refreshInfosHandler = refreshInfosHandler
    }

    func createBackup() throws -> URL {
        let backupManager = BackupManager(dataProvider: store.dataProvider)
        return try backupManager.createBackup()
    }

    func createLibraryExport(format: LibraryExportFormat) throws -> URL {
        try LibraryExportManager().createExport(for: store.library, format: format)
    }

    func restoreBackup(from url: URL) throws {
        let accessedSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let backupManager = BackupManager(dataProvider: store.dataProvider)
        try backupManager.restoreBackup(from: url)
        store.reloadPersistedPreferences()
        try store.refreshLibrary()
        if store.autoPrefetchImagesOnAddAndRestore {
            prefetchAllImages()
        }
    }

    func metadataCacheSize() async -> Result<UInt, KingfisherError> {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                continuation.resume(returning: result)
            }
        }
    }

    func clearMetadataCache() {
        KingfisherManager.shared.cache.clearCache()
    }

    /// Runs the canonical metadata refresh flow for the current library.
    /// Production uses `performRefreshInfos(for:options:)`; tests can inject a stub.
    func refreshInfos(options: LibraryRefreshOptions = .toastDefault) {
        refreshInfosHandler(store, options)
    }

    /// Builds the narrow action surface used by the What's New modal.
    /// The refresh CTA deliberately reuses `refreshInfos()` so there is only
    /// one in-app metadata refresh path to maintain.
    func makeWhatsNewActionRunner() -> WhatsNewActionRunner {
        WhatsNewActionRunner(
            refreshMetadata: { options in
                self.refreshInfos(options: options)
            }
        )
    }

    /// Default production implementation for `refreshInfos(options:)`.
    /// Refreshes visible library metadata and prefetches any updated images.
    private static func performRefreshInfos(
        for store: LibraryStore,
        options: LibraryRefreshOptions
    ) {
        let metadataRefresher = LibraryMetadataRefresher(repository: store.repository)
        Task {
            await metadataRefresher.refreshInfos(
                for: store.library,
                fetcher: store.infoFetcher,
                language: store.language,
                options: options
            )
        }
    }

    func clearLibrary() {
        let cachedImageURLs = Set(store.library.flatMap { LibraryImageCacheService.relatedImageURLs(for: $0) })
        do {
            try store.repository.clearLibrary()
            LibraryImageCacheService.removeCachedImages(for: cachedImageURLs)
        } catch {
            libraryStoreLogger.error("Error clearing library: \(error)")
            ToastCenter.global.completionState = .failed(message: error.localizedDescription)
        }
    }

    func prefetchAllImages(reporter: LibraryRefreshReporter = .toast) {
        LibraryImageCacheService.prefetchImages(
            for: store.library,
            reporter: reporter
        )
    }
}
