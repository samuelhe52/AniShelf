//
//  LibraryProfileSettingsView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/3.
//

import DataProvider
import Kingfisher
import SwiftUI

struct LibraryProfileSettingsView: View {
    @Bindable var store: LibraryStore
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()

    @State private var changeAPIKey = false
    @State private var showCacheAlert = false
    @State private var showClearAllAlert = false
    @State private var exportError: Error? = nil
    @State private var showExportError = false
    @State private var restoreError: Error? = nil
    @State private var showRestoreError = false
    @State private var showFileImporter = false
    @State private var restoreFileURL: URL? = nil
    @State private var showRestoreConfirmation = false
    @State private var showRefreshInfoOnLanguageUpdateAlert = false
    @State private var showRefreshInfoAlert = false
    @State private var showAboutSheet = false
    @State private var cacheSizeResult: Result<UInt, KingfisherError>? = nil
    @State private var appeared = false
    @SceneStorage("LibraryProfileSettingsView.restoreCompleted") private var restoreCompleted = false

    private var stats: LibraryProfileStats {
        LibraryProfileStats(entries: store.library)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryProfileBackdrop(reduceMotion: reduceMotion)

                ScrollView {
                    VStack(spacing: 16) {
                        heroCard
                            .profileReveal(index: 0, appeared: appeared, reduceMotion: reduceMotion)
                        primaryStatsGrid
                            .profileReveal(index: 1, appeared: appeared, reduceMotion: reduceMotion)
                        libraryDetailsCard
                            .profileReveal(index: 2, appeared: appeared, reduceMotion: reduceMotion)
                        settingsCard
                            .profileReveal(index: 3, appeared: appeared, reduceMotion: reduceMotion)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(profileTitleResource)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(closeTitleResource))
                }
            }
            .onAppear {
                store.language = effectiveLanguage
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                    appeared = true
                }
            }
            .onChange(of: preferredLanguage) { old, new in
                guard old != new, !followsSystemLanguage else { return }
                store.language = new
                showRefreshInfoOnLanguageUpdateAlert = true
            }
            .onChange(of: followsSystemLanguage) { old, new in
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
        }
        .alert("Delete all animes?", isPresented: $showClearAllAlert) {
            Button("Delete", role: .destructive) {
                store.clearLibrary()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Refresh Info Language?",
            isPresented: $showRefreshInfoOnLanguageUpdateAlert
        ) {
            Button("Refresh") {
                store.refreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let message: LocalizedStringResource = """
                Changing the metadata language setting will not refresh existing infos.
                Refresh all anime infos now? This may take considerable time.
                """

            Text(message)
        }
        .alert(
            "Refresh all anime infos?",
            isPresented: $showRefreshInfoAlert
        ) {
            Button("Refresh") {
                store.refreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may take considerable time.")
        }
        .alert(
            "Error exporting library",
            isPresented: $showExportError,
            presenting: exportError
        ) { _ in
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert(
            "Error restoring library",
            isPresented: $showRestoreError,
            presenting: restoreError
        ) { _ in
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Overwrite the current library?", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm", role: .destructive, action: restore)
        } message: {
            Text("Please backup the current library before proceeding.")
        }
        .alert(
            "Metadata Cache Size", isPresented: $showCacheAlert, presenting: cacheSizeResult,
            actions: { result in
                switch result {
                case .success:
                    Button("Clear Cache") {
                        KingfisherManager.shared.cache.clearCache()
                    }
                    Button("Cancel", role: .cancel) {}
                case .failure:
                    Button("OK") {}
                }
            },
            message: { result in
                switch result {
                case .success(let size):
                    Text("Size: \(Double(size) / 1024 / 1024, specifier: "%.2f") MB")
                case .failure(let error):
                    Text(error.localizedDescription)
                }
            }
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.mallib]
        ) { result in
            processFileImport(result)
        }
        .sheet(isPresented: $changeAPIKey) {
            TMDbAPIConfigurator()
                .presentationDetents([.fraction(0.65), .large])
        }
        .sheet(isPresented: $showAboutSheet) {
            NavigationStack {
                AboutAniShelfSheet()
            }
            .presentationDetents([.fraction(0.85), .large])
        }
    }

    private var heroCard: some View {
        LibraryProfileHeroCard(
            stats: stats,
            animeTitleResource: animeTitleResource
        )
    }

    private var primaryStatsGrid: some View {
        LibraryProfilePrimaryStatsGrid(stats: stats)
    }

    private var libraryDetailsCard: some View {
        LibraryProfileLibraryDetailsCard(
            stats: stats,
            runtimeDescription: runtimeDescription
        )
    }

    private var settingsCard: some View {
        LibraryProfileSettingsCard(
            followsSystemLanguage: followsSystemLanguageBinding,
            hideDroppedByDefault: $store.hideDroppedByDefault,
            defaultNewEntryWatchStatus: $store.defaultNewEntryWatchStatus,
            defaultFilters: $store.defaultFilters,
            autoPrefetchImagesOnAddAndRestore: $store.autoPrefetchImagesOnAddAndRestore,
            preferredLanguage: $preferredLanguage,
            restoreCompleted: restoreCompleted,
            createBackupItems: makeBackupExportItems,
            onRestore: {
                restoreCompleted = false
                showFileImporter = true
            },
            onChangeAPIKey: {
                changeAPIKey = true
            },
            onCheckMetadataCacheSize: calculateCacheSize,
            onRefreshInfos: {
                showRefreshInfoAlert = true
            },
            onPrefetchImages: {
                store.prefetchAllImages()
            },
            onShowAbout: {
                showAboutSheet = true
            },
            onDeleteAllAnimes: {
                showClearAllAlert = true
            }
        )
        .animation(languagePickerAnimation, value: followsSystemLanguage)
    }

    private var followsSystemLanguageBinding: Binding<Bool> {
        Binding(
            get: { followsSystemLanguage },
            set: { newValue in
                withAnimation(languagePickerAnimation) {
                    followsSystemLanguage = newValue
                }
            }
        )
    }

    private var languagePickerAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88)
    }

    private var effectiveLanguage: Language {
        followsSystemLanguage ? .current : preferredLanguage
    }

    private func resolvedLanguage(followsSystem: Bool, preferredLanguage: Language) -> Language {
        followsSystem ? .current : preferredLanguage
    }

    private var runtimeDescription: String {
        guard stats.runtimeMinutes > 0 else { return String(localized: "N/A") }
        let hours = stats.runtimeMinutes / 60
        let minutes = stats.runtimeMinutes % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func makeBackupExportItems() -> [Any]? {
        do {
            let url = try store.backupManager.createBackup()
            return [url]
        } catch {
            presentExportError(error)
            return nil
        }
    }

    private func calculateCacheSize() {
        KingfisherManager.shared.cache.calculateDiskStorageSize { result in
            DispatchQueue.main.async {
                cacheSizeResult = result
                showCacheAlert = true
            }
        }
    }

    private func processFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            restoreFileURL = url
            showRestoreConfirmation = true
        case .failure(let error):
            presentRestoreError(error)
        }
    }

    private func presentExportError(_ error: Error) {
        exportError = error
        showExportError = true
    }

    private func presentRestoreError(_ error: Error) {
        restoreError = error
        showRestoreError = true
    }

    private func restore() {
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
            try store.backupManager.restoreBackup(from: url)
            store.reloadPersistedPreferences()
            try store.refreshLibrary()
            if store.autoPrefetchImagesOnAddAndRestore {
                store.prefetchAllImages()
            }
            withAnimation {
                restoreCompleted = true
            }
        } catch {
            presentRestoreError(error)
        }
    }

    private var profileTitleResource: LocalizedStringResource {
        "AniShelf Library"
    }

    private var animeTitleResource: LocalizedStringResource {
        "Anime"
    }

    private var closeTitleResource: LocalizedStringResource {
        "Close"
    }
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryProfileSettingsView(store: store)
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
}
