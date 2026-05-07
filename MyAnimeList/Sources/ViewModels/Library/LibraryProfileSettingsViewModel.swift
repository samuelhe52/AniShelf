//
//  LibraryProfileSettingsViewModel.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/7.
//

import Foundation
import Kingfisher
import SwiftUI

@Observable @MainActor
final class LibraryProfileSettingsViewModel {
    var changeAPIKey = false
    var showCacheAlert = false
    var showClearAllAlert = false
    var exportError: Error? = nil
    var showExportError = false
    var restoreError: Error? = nil
    var showRestoreError = false
    var showFileImporter = false
    var restoreFileURL: URL? = nil
    var showRestoreConfirmation = false
    var showRefreshInfoOnLanguageUpdateAlert = false
    var showRefreshInfoAlert = false
    var showTMDbRelayRestartAlert = false
    var showAboutSheet = false
    var cacheSizeResult: Result<UInt, KingfisherError>? = nil
    var appeared = false
    var restoreCompleted = false

    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
    }

    func onAppear(effectiveLanguage: Language, reduceMotion: Bool) {
        store.language = effectiveLanguage
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            appeared = true
        }
    }

    func handlePreferredLanguageChange(
        old: Language,
        new: Language,
        followsSystem: Bool
    ) {
        guard old != new, !followsSystem else { return }
        store.language = new
        showRefreshInfoOnLanguageUpdateAlert = true
    }

    func handleFollowsSystemLanguageChange(
        old: Bool,
        new: Bool,
        preferredLanguage: Language
    ) {
        guard old != new else { return }
        let oldLanguage = resolvedLanguage(
            followsSystem: old,
            preferredLanguage: preferredLanguage
        )
        let newLanguage = resolvedLanguage(
            followsSystem: new,
            preferredLanguage: preferredLanguage
        )
        store.language = new ? .current : preferredLanguage
        guard oldLanguage != newLanguage else { return }
        showRefreshInfoOnLanguageUpdateAlert = true
    }

    func handleTMDbRelayServerChange(old: Bool, new: Bool) {
        guard old != new else { return }
        NotificationCenter.default.post(
            name: .tmdbAPIConfigurationDidChange,
            object: nil
        )
        showTMDbRelayRestartAlert = true
    }

    func prepareBackupExportItems() -> [Any]? {
        do {
            let url = try store.createBackup()
            return [url]
        } catch {
            presentExportError(error)
            return nil
        }
    }

    func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            restoreFileURL = url
            showRestoreConfirmation = true
        case .failure(let error):
            presentRestoreError(error)
        }
    }

    func restoreSelectedBackup() {
        restoreCompleted = false
        guard let url = restoreFileURL else { return }
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: .bundleIdentifier,
                    code: 1,
                    userInfo: [url.path(): "Access denied to URL"]
                )
            }
            defer { url.stopAccessingSecurityScopedResource() }
            try store.restoreBackup(from: url)
            withAnimation {
                restoreCompleted = true
            }
        } catch {
            presentRestoreError(error)
        }
    }

    func calculateCacheSize() {
        KingfisherManager.shared.cache.calculateDiskStorageSize { [weak self] result in
            DispatchQueue.main.async {
                self?.cacheSizeResult = result
                self?.showCacheAlert = true
            }
        }
    }

    func clearMetadataCache() {
        KingfisherManager.shared.cache.clearCache()
    }

    func requestRefreshInfos() {
        showRefreshInfoAlert = true
    }

    func confirmRefreshInfos() {
        store.refreshInfos()
    }

    func requestClearLibrary() {
        showClearAllAlert = true
    }

    func confirmClearLibrary() {
        store.clearLibrary()
    }

    func requestRestore() {
        restoreCompleted = false
        showFileImporter = true
    }

    func showAPIKeySheet() {
        changeAPIKey = true
    }

    func prefetchImages() {
        store.prefetchAllImages()
    }

    func showAbout() {
        showAboutSheet = true
    }

    private func resolvedLanguage(followsSystem: Bool, preferredLanguage: Language) -> Language {
        followsSystem ? .current : preferredLanguage
    }

    private func presentExportError(_ error: Error) {
        exportError = error
        showExportError = true
    }

    private func presentRestoreError(_ error: Error) {
        restoreError = error
        showRestoreError = true
    }
}
