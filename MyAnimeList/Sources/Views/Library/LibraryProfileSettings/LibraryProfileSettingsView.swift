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
    var onDismiss: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false
    @AppStorage(.entryDetailCharactersExpandedByDefault)
    private var entryDetailCharactersExpandedByDefault = true
    @AppStorage(.entryDetailStaffExpandedByDefault)
    private var entryDetailStaffExpandedByDefault = false
    @AppStorage(.useTMDbRelayServer) private var useTMDbRelayServer = true

    @State private var changeAPIKey = false
    @State private var showCacheAlert = false
    @State private var showClearAllAlert = false
    @State private var exportError: Error?
    @State private var showExportError = false
    @State private var restoreError: Error?
    @State private var showRestoreError = false
    @State private var showFileImporter = false
    @State private var restoreFileURL: URL?
    @State private var showRestoreConfirmation = false
    @State private var showRefreshInfoOnLanguageUpdateAlert = false
    @State private var showRefreshInfoAlert = false
    @State private var showTMDbRelayRestartAlert = false
    @State private var showAboutSheet = false
    @State private var cacheSizeResult: Result<UInt, KingfisherError>?
    @State private var appeared = false
    @State private var restoreCompleted = false

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var stats: LibraryProfileStats {
        LibraryProfileStats(entries: store.library)
    }

    private var actions: LibraryProfileSettingsActions {
        LibraryProfileSettingsActions(store: store)
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
                    Button(action: dismissSettings) {
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
            .onAppear(perform: handleAppear)
            .onChange(of: preferredLanguage, handlePreferredLanguageChange)
            .onChange(of: followsSystemLanguage, handleFollowsSystemLanguageChange)
        }
        .alert("Delete all animes?", isPresented: $showClearAllAlert) {
            Button("Delete", role: .destructive, action: confirmClearLibrary)
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Refresh Info Language?",
            isPresented: $showRefreshInfoOnLanguageUpdateAlert
        ) {
            Button("Refresh", action: confirmRefreshInfos)
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
            Button("Refresh", action: confirmRefreshInfos)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may take considerable time.")
        }
        .alert("TMDb Proxy Updated", isPresented: $showTMDbRelayRestartAlert) {
            Button("OK") {}
        } message: {
            Text("You might need to restart the app for this change to take effect.")
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
            Button("Confirm", role: .destructive, action: confirmRestore)
        } message: {
            Text("Please backup the current library before proceeding.")
        }
        .alert(
            "Metadata Cache Size",
            isPresented: $showCacheAlert,
            presenting: cacheSizeResult,
            actions: { result in
                switch result {
                case .success:
                    Button("Clear Cache", action: clearMetadataCache)
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
            allowedContentTypes: [.mallib],
            onCompletion: handleFileImport
        )
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
            runtimeDescription: stats.runtimeDescription
        )
    }

    @ViewBuilder
    private var settingsCard: some View {
        @Bindable var store = store

        LibraryProfileSettingsCard(
            followsSystemLanguage: followsSystemLanguageBinding,
            hideDroppedByDefault: $store.hideDroppedByDefault,
            defaultNewEntryWatchStatus: $store.defaultNewEntryWatchStatus,
            defaultFilters: $store.defaultFilters,
            openDetailWithSingleTap: $openDetailWithSingleTap,
            entryDetailCharactersExpandedByDefault: $entryDetailCharactersExpandedByDefault,
            entryDetailStaffExpandedByDefault: $entryDetailStaffExpandedByDefault,
            autoPrefetchImagesOnAddAndRestore: $store.autoPrefetchImagesOnAddAndRestore,
            useTMDbRelayServer: $useTMDbRelayServer,
            preferredLanguage: $preferredLanguage,
            restoreCompleted: restoreCompleted,
            createBackupItems: createBackupItems,
            onRestore: requestRestore,
            onChangeAPIKey: requestAPIKeySheet,
            onCheckMetadataCacheSize: checkMetadataCacheSize,
            onRefreshInfos: requestRefreshInfos,
            onPrefetchImages: actions.prefetchAllImages,
            onShowAbout: presentAboutSheet,
            onDeleteAllAnimes: requestClearLibrary
        )
        .animation(languagePickerAnimation, value: followsSystemLanguage)
        .onChange(of: useTMDbRelayServer, handleTMDbRelayServerChange)
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

    private var profileTitleResource: LocalizedStringResource {
        "AniShelf Library"
    }

    private var animeTitleResource: LocalizedStringResource {
        "Anime"
    }

    private var closeTitleResource: LocalizedStringResource {
        "Close"
    }

    private func dismissSettings() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func handleAppear() {
        store.language = effectiveLanguage
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            appeared = true
        }
    }

    private func handlePreferredLanguageChange(old: Language, new: Language) {
        guard old != new, !followsSystemLanguage else { return }
        store.language = new
        showRefreshInfoOnLanguageUpdateAlert = true
    }

    private func handleFollowsSystemLanguageChange(old: Bool, new: Bool) {
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

    private func handleTMDbRelayServerChange(old: Bool, new: Bool) {
        guard old != new else { return }
        NotificationCenter.default.post(
            name: .tmdbAPIConfigurationDidChange,
            object: nil
        )
        showTMDbRelayRestartAlert = true
    }

    private func requestAPIKeySheet() {
        changeAPIKey = true
    }

    private func requestRestore() {
        restoreCompleted = false
        showFileImporter = true
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            restoreFileURL = url
            showRestoreConfirmation = true
        case .failure(let error):
            presentRestoreError(error)
        }
    }

    private func confirmRestore() {
        restoreCompleted = false
        guard let restoreFileURL else { return }
        do {
            try actions.restoreBackup(from: restoreFileURL)
            withAnimation {
                restoreCompleted = true
            }
        } catch {
            presentRestoreError(error)
        }
    }

    private func requestRefreshInfos() {
        showRefreshInfoAlert = true
    }

    private func confirmRefreshInfos() {
        actions.refreshInfos()
    }

    private func checkMetadataCacheSize() {
        Task { @MainActor in
            cacheSizeResult = await actions.metadataCacheSize()
            showCacheAlert = true
        }
    }

    private func clearMetadataCache() {
        actions.clearMetadataCache()
    }

    private func requestClearLibrary() {
        showClearAllAlert = true
    }

    private func confirmClearLibrary() {
        actions.clearLibrary()
    }

    private func presentAboutSheet() {
        showAboutSheet = true
    }

    private func createBackupItems() -> [Any]? {
        do {
            return [try actions.createBackup()]
        } catch {
            presentExportError(error)
            return nil
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

    private func resolvedLanguage(
        followsSystem: Bool,
        preferredLanguage: Language
    ) -> Language {
        followsSystem ? .current : preferredLanguage
    }
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryProfileSettingsView()
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(store)
}
