//
//  LibraryProfileSettingsActions.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/7.
//

import DataProvider
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
    /// Refreshes all persisted entries and prefetches any updated images.
    ///
    /// Hidden helper rows are intentionally included, even when they are not currently visible.
    /// Some season entries still rely on those rows for parent-series relationships, so skipping
    /// them here can leave the store in a partially refreshed state.
    private static func performRefreshInfos(
        for store: LibraryStore,
        options: LibraryRefreshOptions
    ) {
        let metadataRefresher = LibraryMetadataRefresher(repository: store.repository)
        Task {
            do {
                let entries = try getRefreshEntries(for: store)
                await metadataRefresher.refreshInfos(
                    for: entries,
                    fetcher: store.infoFetcher,
                    language: store.language,
                    options: options
                )
            } catch {
                libraryStoreLogger.error(
                    "Failed to load refresh entries: \(error.localizedDescription)"
                )
                options.reporter.report(
                    .refreshComplete(
                        .init(
                            state: .failed,
                            messageResource: LocalizedStringResource(
                                stringLiteral: error.localizedDescription
                            )
                        )
                    )
                )
            }
        }
    }

    static func getRefreshEntries(for store: LibraryStore) throws -> [AnimeEntry] {
        // Refresh the full persisted set, not just `store.library`.
        // Hidden helper parents may still be required by season entries, including rows that are
        // not currently surfaced in the visible library UI.
        try store.dataProvider.getAllModels(ofType: AnimeEntry.self)
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
