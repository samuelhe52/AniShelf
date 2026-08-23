//
//  LibraryProfileSettingsCard.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

struct LibraryProfileSettingsCard: View {
    enum Layout {
        case compactCard
        case workspaceGrid
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var cloudSyncActionInFlight = false
    @State private var showCloudSyncConflictAlert = false
    @State private var showRestoreUnavailableAlert = false

    @Binding var followsSystemLanguage: Bool
    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>
    @Binding var autoPrefetchImagesOnAddAndRestore: Bool
    @Binding var longTermGalleryPosterCachingEnabled: Bool
    @Binding var preferredLanguage: Language

    let layout: Layout
    let libraryCloudSyncStatus: LibraryCloudSyncStatus
    let restoreCompleted: Bool
    let createBackupItems: () -> [Any]?
    let onExportLibrary: (LibraryExportFormat) -> Void
    let onRestore: () -> Void
    let onEnableLibraryCloudSync: () async -> Bool
    let onDisableLibraryCloudSync: () -> Void
    let onRetryLibraryCloudSync: () async -> Bool
    let onResolveLibraryCloudSyncConflicts: (LibraryCloudSyncConflictPreference) async -> Bool
    let onCancelLibraryCloudSyncEnablement: () -> Void
    let onChangeAPIKey: () -> Void
    let onCheckMetadataCacheSize: () -> Void
    let onRefreshInfos: () -> Void
    let onPrefetchImages: () -> Void
    let onShowSupport: () -> Void
    let whatsNewVersion: String?
    let onShowWhatsNew: () -> Void
    let onShowAbout: () -> Void
    let onDeleteAllAnimes: () -> Void

    var body: some View {
        settingsContent
            .alert("Resolve iCloud Sync Conflict", isPresented: $showCloudSyncConflictAlert) {
                Button("Use iCloud") {
                    resolveLibraryCloudSyncConflicts(.preferCloud)
                }
                Button("Use This Device") {
                    resolveLibraryCloudSyncConflicts(.preferLocal)
                }
                Button("Cancel", role: .cancel, action: cancelLibraryCloudSyncEnablement)
            } message: {
                Text(libraryCloudSyncStatus.conflictSummaryResource)
            }
            .alert("Restore Unavailable", isPresented: $showRestoreUnavailableAlert) {
                Button("OK") {}
            } message: {
                Text(
                    "Turn off iCloud Sync before restoring a backup. You can turn it on again after restore."
                )
            }
            .onAppear(perform: updateCloudSyncConflictAlertPresentation)
            .onChange(of: libraryCloudSyncStatus.bootstrapState) {
                updateCloudSyncConflictAlertPresentation()
            }
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch layout {
        case .compactCard:
            PopupSectionCard(
                "Settings",
                systemImage: "gearshape.2",
                spacing: 14,
                panelTint: sectionCardTint
            ) {
                VStack(spacing: 14) {
                    settingsSections
                }
            }
        case .workspaceGrid:
            VStack(alignment: .leading, spacing: 14) {
                Label("Settings", systemImage: "gearshape.2")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                workspaceSettingsColumns
            }
        }
    }

    @ViewBuilder
    private var settingsSections: some View {
        languageSettingsSection
        preferencesSection
        airingReminderSettingsSection
        interfaceSettingsSection
        tmdbConnectionSection
        iCloudSyncSection
        backupExportSection
        maintenanceActionsSection
    }

    private var languageSettingsSection: some View {
        LibraryProfileLanguageSettingsSection(
            followsSystemLanguage: $followsSystemLanguage,
            preferredLanguage: $preferredLanguage
        )
    }

    private var preferencesSection: some View {
        LibraryProfilePreferencesSection(
            hideDroppedByDefault: $hideDroppedByDefault,
            defaultNewEntryWatchStatus: $defaultNewEntryWatchStatus,
            defaultFilters: $defaultFilters,
            autoPrefetchImagesOnAddAndRestore: $autoPrefetchImagesOnAddAndRestore,
            longTermGalleryPosterCachingEnabled: $longTermGalleryPosterCachingEnabled
        )
    }

    private var interfaceSettingsSection: some View {
        LibraryProfileInterfaceSettingsSection()
    }

    private var airingReminderSettingsSection: some View {
        LibraryProfileAiringReminderSettingsSection()
    }

    private var tmdbConnectionSection: some View {
        LibraryProfileTMDbConnectionSection()
    }

    private var iCloudSyncSection: some View {
        LibraryProfileICloudSyncSection(
            libraryCloudSyncStatus: libraryCloudSyncStatus,
            cloudSyncToggleBinding: cloudSyncToggleBinding,
            cloudSyncToggleDisabled: cloudSyncToggleDisabled,
            cloudSyncToggleSubtitle: cloudSyncToggleSubtitle,
            cloudSyncIsBusy: cloudSyncIsBusy,
            cloudSyncStatusTitleColor: cloudSyncStatusTitleColor,
            cloudSyncManualRetryDisabled: cloudSyncManualRetryDisabled,
            onRetryLibraryCloudSync: retryLibraryCloudSync
        )
    }

    private var backupExportSection: some View {
        LibraryProfileBackupExportSection(
            libraryCloudSyncStatus: libraryCloudSyncStatus,
            restoreCompleted: restoreCompleted,
            createBackupItems: createBackupItems,
            onExportLibrary: onExportLibrary,
            onRestoreButtonPress: handleRestoreButtonPress
        )
    }

    private var maintenanceActionsSection: some View {
        LibraryProfileMaintenanceActionsSection(
            onChangeAPIKey: onChangeAPIKey,
            onCheckMetadataCacheSize: onCheckMetadataCacheSize,
            onRefreshInfos: onRefreshInfos,
            onPrefetchImages: onPrefetchImages,
            onShowSupport: onShowSupport,
            whatsNewVersion: whatsNewVersion,
            onShowWhatsNew: onShowWhatsNew,
            onShowAbout: onShowAbout,
            onDeleteAllAnimes: onDeleteAllAnimes
        )
    }

    private var workspaceSettingsColumns: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                languageSettingsSection
                preferencesSection
                airingReminderSettingsSection
                interfaceSettingsSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(spacing: 20) {
                iCloudSyncSection
                backupExportSection
                tmdbConnectionSection
                maintenanceActionsSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func handleRestoreButtonPress() {
        if libraryCloudSyncStatus.blocksBackupRestore {
            showRestoreUnavailableAlert = true
        } else {
            onRestore()
        }
    }

    private var sectionCardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }

    private var cloudSyncToggleBinding: Binding<Bool> {
        Binding(
            get: { libraryCloudSyncStatus.isEnabled },
            set: { isEnabled in
                if isEnabled {
                    enableLibraryCloudSync()
                } else {
                    onDisableLibraryCloudSync()
                }
            }
        )
    }

    private var cloudSyncIsBusy: Bool {
        cloudSyncActionInFlight || libraryCloudSyncStatus.isSyncInProgress
    }

    private var cloudSyncManualRetryDisabled: Bool {
        cloudSyncIsBusy || libraryCloudSyncStatus.bootstrapState == .needsConflictChoice
    }

    private var cloudSyncToggleDisabled: Bool {
        !libraryCloudSyncStatus.isEnabled && cloudSyncIsBusy
    }

    private var cloudSyncToggleSubtitle: LocalizedStringResource {
        "Existing iCloud data stays untouched."
    }

    private var cloudSyncStatusTitleColor: Color {
        switch libraryCloudSyncStatus.bootstrapState {
        case .needsConflictChoice:
            .orange.opacity(colorScheme == .dark ? 0.82 : 0.74)
        case .failed:
            .red.opacity(colorScheme == .dark ? 0.84 : 0.76)
        case .completed:
            switch libraryCloudSyncStatus.lastResult {
            case .retryableFailure, .permanentFailure:
                .red.opacity(colorScheme == .dark ? 0.84 : 0.76)
            case .success, .skipped, .conflictChoiceRequired, nil:
                .secondary
            }
        case .notStarted, .running:
            .secondary
        }
    }

    private func enableLibraryCloudSync() {
        guard !cloudSyncIsBusy else { return }
        cloudSyncActionInFlight = true
        Task {
            _ = await onEnableLibraryCloudSync()
            cloudSyncActionInFlight = false
        }
    }

    private func retryLibraryCloudSync() {
        guard !cloudSyncManualRetryDisabled else { return }
        cloudSyncActionInFlight = true
        Task {
            _ = await onRetryLibraryCloudSync()
            cloudSyncActionInFlight = false
        }
    }

    private func resolveLibraryCloudSyncConflicts(_ preference: LibraryCloudSyncConflictPreference) {
        guard !cloudSyncActionInFlight else { return }
        cloudSyncActionInFlight = true
        Task {
            _ = await onResolveLibraryCloudSyncConflicts(preference)
            cloudSyncActionInFlight = false
        }
    }

    private func cancelLibraryCloudSyncEnablement() {
        showCloudSyncConflictAlert = false
        onCancelLibraryCloudSyncEnablement()
    }

    private func updateCloudSyncConflictAlertPresentation() {
        showCloudSyncConflictAlert = libraryCloudSyncStatus.bootstrapState == .needsConflictChoice
    }
}
