//
//  LibraryProfileSettingsView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/3.
//

import DataProvider
import SwiftUI

struct LibraryProfileSettingsView: View {
    @Bindable var store: LibraryStore
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.useTMDbRelayServer) private var useTMDbRelayServer = true

    @State private var viewModel: LibraryProfileSettingsViewModel

    init(store: LibraryStore, onDismiss: (() -> Void)? = nil) {
        self.store = store
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: LibraryProfileSettingsViewModel(store: store))
    }

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
                            .profileReveal(index: 0, appeared: viewModel.appeared, reduceMotion: reduceMotion)
                        primaryStatsGrid
                            .profileReveal(index: 1, appeared: viewModel.appeared, reduceMotion: reduceMotion)
                        libraryDetailsCard
                            .profileReveal(index: 2, appeared: viewModel.appeared, reduceMotion: reduceMotion)
                        settingsCard
                            .profileReveal(index: 3, appeared: viewModel.appeared, reduceMotion: reduceMotion)
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
                viewModel.onAppear(effectiveLanguage: effectiveLanguage, reduceMotion: reduceMotion)
            }
            .onChange(of: preferredLanguage) { old, new in
                viewModel.handlePreferredLanguageChange(
                    old: old,
                    new: new,
                    followsSystem: followsSystemLanguage
                )
            }
            .onChange(of: followsSystemLanguage) { old, new in
                viewModel.handleFollowsSystemLanguageChange(
                    old: old,
                    new: new,
                    preferredLanguage: preferredLanguage
                )
            }
        }
        .alert("Delete all animes?", isPresented: $viewModel.showClearAllAlert) {
            Button("Delete", role: .destructive) {
                viewModel.confirmClearLibrary()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Refresh Info Language?",
            isPresented: $viewModel.showRefreshInfoOnLanguageUpdateAlert
        ) {
            Button("Refresh") {
                viewModel.confirmRefreshInfos()
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
            isPresented: $viewModel.showRefreshInfoAlert
        ) {
            Button("Refresh") {
                viewModel.confirmRefreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may take considerable time.")
        }
        .alert("TMDb Proxy Updated", isPresented: $viewModel.showTMDbRelayRestartAlert) {
            Button("OK") {}
        } message: {
            Text("You might need to restart the app for this change to take effect.")
        }
        .alert(
            "Error exporting library",
            isPresented: $viewModel.showExportError,
            presenting: viewModel.exportError
        ) { _ in
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert(
            "Error restoring library",
            isPresented: $viewModel.showRestoreError,
            presenting: viewModel.restoreError
        ) { _ in
            Button("Cancel", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Overwrite the current library?", isPresented: $viewModel.showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm", role: .destructive, action: viewModel.restoreSelectedBackup)
        } message: {
            Text("Please backup the current library before proceeding.")
        }
        .alert(
            "Metadata Cache Size", isPresented: $viewModel.showCacheAlert, presenting: viewModel.cacheSizeResult,
            actions: { result in
                switch result {
                case .success:
                    Button("Clear Cache") {
                        viewModel.clearMetadataCache()
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
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.mallib]
        ) { result in
            viewModel.handleFileImport(result)
        }
        .sheet(isPresented: $viewModel.changeAPIKey) {
            TMDbAPIConfigurator()
                .presentationDetents([.fraction(0.65), .large])
        }
        .sheet(isPresented: $viewModel.showAboutSheet) {
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

    private var settingsCard: some View {
        LibraryProfileSettingsCard(
            followsSystemLanguage: followsSystemLanguageBinding,
            hideDroppedByDefault: $store.hideDroppedByDefault,
            defaultNewEntryWatchStatus: $store.defaultNewEntryWatchStatus,
            defaultFilters: $store.defaultFilters,
            autoPrefetchImagesOnAddAndRestore: $store.autoPrefetchImagesOnAddAndRestore,
            useTMDbRelayServer: $useTMDbRelayServer,
            preferredLanguage: $preferredLanguage,
            restoreCompleted: viewModel.restoreCompleted,
            createBackupItems: viewModel.prepareBackupExportItems,
            onRestore: viewModel.requestRestore,
            onChangeAPIKey: viewModel.showAPIKeySheet,
            onCheckMetadataCacheSize: viewModel.calculateCacheSize,
            onRefreshInfos: viewModel.requestRefreshInfos,
            onPrefetchImages: viewModel.prefetchImages,
            onShowAbout: viewModel.showAbout,
            onDeleteAllAnimes: viewModel.requestClearLibrary
        )
        .animation(languagePickerAnimation, value: followsSystemLanguage)
        .onChange(of: useTMDbRelayServer) { old, new in
            viewModel.handleTMDbRelayServerChange(old: old, new: new)
        }
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
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryProfileSettingsView(store: store)
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
}
