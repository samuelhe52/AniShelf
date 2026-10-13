//
//  LibraryProfileSettingsView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/3.
//

import DataProvider
import Kingfisher
import SwiftUI

struct LibraryProfileSettingsView: View {
    var onDismiss: (() -> Void)? = nil

    @Environment(LibraryStore.self) private var store
    @Environment(WhatsNewController.self) private var whatsNew
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.windowSceneIdentifier) private var windowSceneIdentifier
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false

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
    @State private var presentationState = LibraryProfileSettingsPresentationState()
    @State private var cacheSizeResult: Result<UInt, KingfisherError>?
    @State private var appeared = false
    @State private var path: [LibraryProfileSettingsDestination] = []
    @State private var cloudSync = LibraryProfileCloudSyncController()
    @State private var remindersLoaded = false
    private let airingReminders = AiringReminderCoordinator.shared
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
        NavigationStack(path: $path) {
            ZStack {
                LibraryProfileBackdrop()

                ScrollView {
                    profileContent
                }
                .scrollContentBackground(.hidden)
                .preferredNavigationBarScrollEdgeEffect()
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
            .navigationDestination(for: LibraryProfileSettingsDestination.self) { destination in
                settingsPage(for: destination)
            }
        }
        .onAppear(perform: handleAppear)
        .onChange(of: preferredLanguage, handlePreferredLanguageChange)
        .onChange(of: followsSystemLanguage, handleFollowsSystemLanguageChange)
        .task { await reloadReminders() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reloadReminders() }
        }
        .task(id: store.libraryCloudSyncStatus.bootstrapState) {
            await presentPendingCloudConflict()
        }
        .alert("Resolve iCloud Sync Conflict", isPresented: $cloudSync.showConflictAlert) {
            Button("Use iCloud") { resolveLibraryCloudSyncConflicts(.preferCloud) }
            Button("Use This Device") { resolveLibraryCloudSyncConflicts(.preferLocal) }
            Button("Cancel", role: .cancel, action: cancelLibraryCloudSyncEnablement)
        } message: {
            Text(store.libraryCloudSyncStatus.conflictSummaryResource)
        }
        .alert("Restore Unavailable", isPresented: $cloudSync.showRestoreUnavailableAlert) {
            Button("OK") {}
        } message: {
            Text("Turn off iCloud Sync before restoring a backup. You can turn it on again after restore.")
        }
        .alert("Rebuild iCloud Sync?", isPresented: $cloudSync.showRebuildAlert) {
            Button("Rebuild", action: rebuildLibraryCloudSync)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Refetch and reconcile your iCloud library with your local library. This may resolve some iCloud sync issues."
            )
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
        .sheet(item: $presentationState.presentedSheet) { sheet in
            sheetView(for: sheet)
        }
    }

    private var profileContent: some View {
        VStack(spacing: 16) {
            LibraryProfileHeroCard(stats: stats, animeTitleResource: animeTitleResource)
                .profileReveal(index: 0, appeared: appeared)

            summaryLayout {
                LibraryProfilePrimaryStatsGrid(
                    stats: stats,
                    layout: layout == .workspace ? .fillsSummaryHeight : .compact
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .profileReveal(index: 1, appeared: appeared)
                LibraryProfileLibraryDetailsCard(stats: stats)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .profileReveal(index: 2, appeared: appeared)
            }

            Group {
                switch layout {
                case .hub:
                    LibraryProfileSettingsHub(
                        followsSystemLanguage: followsSystemLanguageBinding,
                        preferredLanguage: $preferredLanguage,
                        remindersLoaded: remindersLoaded,
                        syncStatus: store.libraryCloudSyncStatus,
                        whatsNewVersion: whatsNew.currentEntry?.version,
                        onShowWhatsNew: presentWhatsNewSheet,
                        onShowSupport: presentSupportSheet,
                        onShowAbout: presentAboutSheet
                    )
                case .workspace:
                    settingsWorkspace
                }
            }
            .profileReveal(index: 3, appeared: appeared)
        }
        .animation(languagePickerAnimation, value: followsSystemLanguage)
        .frame(maxWidth: layout == .workspace ? 1180 : 720)
        .padding(.horizontal, layout == .workspace ? 28 : 18)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
    }

    /// Regular width keeps the original side-by-side summary; compact stacks it.
    private var summaryLayout: AnyLayout {
        layout == .workspace
            ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 16))
    }

    private var layout: LibraryProfileSettingsLayout {
        LibraryProfileSettingsLayoutPolicy().layout(
            horizontalSizeClass: horizontalSizeClass, dynamicTypeSize: dynamicTypeSize
        )
    }

    private func settingsPage(for destination: LibraryProfileSettingsDestination) -> some View {
        LibraryProfileSettingsPage(destination: destination, onClose: dismissSettings) {
            destinationContent(destination)
        }
        .modifier(settingsContentAnimations)
    }

    /// Regular width keeps the pre-hub layout: every section expanded in two columns,
    /// using the same destination content the hub pushes on compact width.
    private var settingsWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Settings", systemImage: "gearshape.2")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    LibraryProfileLanguageSettingsRow(
                        followsSystemLanguage: followsSystemLanguageBinding, preferredLanguage: $preferredLanguage
                    )
                    .padding(.horizontal, 14)
                    .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileSettingsPalette.language)
                    workspaceGroup(.libraryTracking)
                    workspaceGroup(.reminders)
                    workspaceGroup(.appearance)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(spacing: 20) {
                    workspaceGroup(.syncData)
                    workspaceGroup(.metadataImages)
                    VStack(alignment: .leading, spacing: 10) {
                        workspaceGroupTitle("App Info")
                        LibraryProfileAppInfoCard(
                            style: .panel,
                            whatsNewVersion: whatsNew.currentEntry?.version, onShowWhatsNew: presentWhatsNewSheet,
                            onShowSupport: presentSupportSheet, onShowAbout: presentAboutSheet
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .modifier(settingsContentAnimations)
    }

    /// Titled with the hub row's name so "Settings › Sync & Data" in the guides holds on iPad too.
    private func workspaceGroup(_ destination: LibraryProfileSettingsDestination) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            workspaceGroupTitle(destination.title)
            VStack(spacing: 20) {
                destinationContent(destination)
            }
        }
        .environment(\.libraryProfilePageTint, destination.tint)
    }

    private func workspaceGroupTitle(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var settingsContentAnimations: LibraryProfileSettingsContentAnimations {
        LibraryProfileSettingsContentAnimations(
            animation: languagePickerAnimation,
            episodeProgressTrackingEnabled: episodeProgressTrackingEnabled,
            categoriesEnabled: store.categoriesEnabled,
            categoryStripEnabled: store.categoryStripEnabled,
            libraryCloudSyncStatus: store.libraryCloudSyncStatus
        )
    }

    @ViewBuilder
    private func destinationContent(_ destination: LibraryProfileSettingsDestination) -> some View {
        @Bindable var store = store
        switch destination {
        case .libraryTracking:
            LibraryProfilePreferencesSection(
                hideDroppedByDefault: $store.hideDroppedByDefault,
                defaultNewEntryWatchStatus: $store.defaultNewEntryWatchStatus,
                defaultFilters: $store.defaultFilters
            )
            LibraryProfileSettingsSection(
                "Categories", systemImage: "folder", tint: LibraryProfileSettingsDestination.libraryTracking.tint
            ) {
                LibraryProfileCategorySettingsRows()
            }
            LibraryProfileTrackingSettingsSection()
        case .appearance:
            LibraryProfileInterfaceSettingsSection()
        case .reminders:
            LibraryProfileBroadcastSettingsSection()
            LibraryProfileAiringReminderSettingsSection()
        case .metadataImages:
            LibraryProfileMetadataImagesPage(
                autoPrefetchImagesOnAddAndRestore: $store.autoPrefetchImagesOnAddAndRestore,
                longTermGalleryPosterCachingEnabled: $store.longTermGalleryPosterCachingEnabled,
                onChangeAPIKey: requestAPIKeySheet,
                onCheckMetadataCacheSize: checkMetadataCacheSize,
                onRefreshInfos: requestRefreshInfos,
                onPrefetchImages: { actions.prefetchAllImages() }
            )
        case .syncData:
            syncDataContent
        }
    }

    private var syncDataContent: some View {
        Group {
            LibraryProfileICloudSyncSection(
                libraryCloudSyncStatus: libraryCloudSyncStatus,
                cloudSyncToggleBinding: cloudSyncToggleBinding,
                cloudSyncToggleDisabled: cloudSyncToggleDisabled,
                cloudSyncToggleSubtitle: cloudSyncToggleSubtitle,
                cloudSyncIsBusy: cloudSyncIsBusy,
                cloudSyncStatusTitleColor: cloudSyncStatusTitleColor,
                cloudSyncManualRetryDisabled: cloudSyncManualRetryDisabled,
                onRetryLibraryCloudSync: retryLibraryCloudSync,
                onDiscardFailedEntry: discardFailedEntry,
                onRequestRebuildLibraryCloudSync: requestRebuildLibraryCloudSync
            )
            LibraryProfileBackupExportSection(
                libraryCloudSyncStatus: libraryCloudSyncStatus,
                restoreCompleted: restoreCompleted,
                createBackupItems: createBackupItems,
                onExportLibrary: exportLibrary,
                onRestoreButtonPress: handleRestoreButtonPress
            )
            LibraryProfileActionRow(
                title: "Delete All Animes", subtitle: "Remove every saved library entry.",
                systemImage: "trash", role: .destructive, tint: LibraryProfileSettingsPalette.destructive,
                horizontalPadding: 0,
                action: requestClearLibrary
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileSettingsPalette.destructive)
        }
    }

    private func reloadReminders() async {
        await airingReminders.reloadState()
        remindersLoaded = true
    }

    private var hasPendingPresentation: Bool {
        presentationState.presentedSheet != nil || showFileImporter || showRestoreConfirmation
            || showCacheAlert || showClearAllAlert || showExportError || showRestoreError
            || showRefreshInfoOnLanguageUpdateAlert || showRefreshInfoAlert
            || cloudSync.showRebuildAlert || cloudSync.showRestoreUnavailableAlert
            || whatsNew.presentedEntry(forSceneIdentifier: windowSceneIdentifier) != nil
    }

    private func presentPendingCloudConflict() async {
        guard libraryCloudSyncStatus.bootstrapState == .needsConflictChoice else {
            cloudSync.reconcileConflict(needsChoice: false, presentationBlocked: false)
            return
        }
        // Only poll while a conflict is pending. The actual presenting scene is
        // checked too, including leaf popovers and UIKit activity controllers.
        while !Task.isCancelled {
            let blocked =
                hasPendingPresentation
                || !LibraryProfileCloudSyncController.sceneIsReadyForAlert(windowSceneIdentifier)
            cloudSync.reconcileConflict(needsChoice: true, presentationBlocked: blocked)
            if cloudSync.showConflictAlert { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
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

    private var languagePickerAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88)
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
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
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

    private func requestAPIKeySheet() {
        presentationState.present(.changeAPIKey)
    }

    private func requestRestore() {
        restoreCompleted = false
        do {
            try actions.validateCanRestoreBackup()
        } catch {
            presentRestoreError(error)
            return
        }
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
        presentationState.present(.about)
    }

    private func presentSupportSheet() {
        presentationState.presentSupportSheet()
    }

    private func presentWhatsNewSheet() {
        whatsNew.presentCurrentEntry(inSceneIdentifier: windowSceneIdentifier)
    }

    private func createBackupItems() -> [Any]? {
        do {
            return [try actions.createBackup()]
        } catch {
            presentExportError(error)
            return nil
        }
    }

    private func exportLibrary(as format: LibraryExportFormat) {
        do {
            let exportURL = try actions.createLibraryExport(format: format)
            ShareSheetPresenter.present(items: [exportURL], sceneIdentifier: windowSceneIdentifier)
        } catch {
            presentExportError(error)
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

    private var libraryCloudSyncStatus: LibraryCloudSyncStatus { store.libraryCloudSyncStatus }

    private func handleRestoreButtonPress() {
        if libraryCloudSyncStatus.blocksBackupRestore {
            cloudSync.showRestoreUnavailableAlert = true
        } else {
            requestRestore()
        }
    }

    private func discardFailedEntry(_ entry: LibraryCloudSyncFailedEntry) {
        guard !cloudSyncIsBusy else { return }
        cloudSync.actionInFlight = true
        Task {
            _ = await actions.discardFailedCloudSyncEntry(entry)
            cloudSync.actionInFlight = false
        }
    }

    private var cloudSyncToggleBinding: Binding<Bool> {
        Binding(
            get: { libraryCloudSyncStatus.isEnabled },
            set: { isEnabled in
                if isEnabled {
                    enableLibraryCloudSync()
                } else {
                    actions.disableLibraryCloudSync()
                }
            }
        )
    }

    private var cloudSyncIsBusy: Bool {
        cloudSync.actionInFlight || libraryCloudSyncStatus.isSyncInProgress
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
        cloudSync.actionInFlight = true
        Task {
            _ = await actions.enableLibraryCloudSync()
            cloudSync.actionInFlight = false
        }
    }

    private func retryLibraryCloudSync() {
        guard !cloudSyncManualRetryDisabled else { return }
        cloudSync.actionInFlight = true
        Task {
            _ = await actions.retryLibraryCloudSync()
            cloudSync.actionInFlight = false
        }
    }

    private func requestRebuildLibraryCloudSync() {
        guard !cloudSyncIsBusy else { return }
        cloudSync.showConflictAlert = false
        cloudSync.showRebuildAlert = true
    }

    private func rebuildLibraryCloudSync() {
        guard !cloudSyncIsBusy else { return }
        cloudSync.actionInFlight = true
        Task {
            _ = await actions.rebuildLibraryCloudSync()
            cloudSync.actionInFlight = false
        }
    }

    private func resolveLibraryCloudSyncConflicts(_ preference: LibraryCloudSyncConflictPreference) {
        guard !cloudSync.actionInFlight else { return }
        cloudSync.actionInFlight = true
        Task {
            _ = await actions.resolveLibraryCloudSyncConflicts(preference: preference)
            cloudSync.actionInFlight = false
        }
    }

    private func cancelLibraryCloudSyncEnablement() {
        cloudSync.showConflictAlert = false
        actions.cancelLibraryCloudSyncEnablement()
    }

    @ViewBuilder
    private func sheetView(for sheet: LibraryProfileSettingsSheet) -> some View {
        switch sheet {
        case .changeAPIKey:
            TMDbAPIConfigurator()
                .presentationDetents([.medium, .large])
                .presentationSizing(.form)
        case .support:
            NavigationStack {
                SupportAniShelfSheet()
            }
            .presentationDetents([.fraction(0.72), .large])
            .presentationSizing(.page)
        case .about:
            NavigationStack {
                AboutAniShelfSheet()
            }
            .presentationDetents([.fraction(0.85), .large])
            .presentationSizing(.form)
        }
    }
}

#Preview {
    @Previewable let store = LibraryStore(dataProvider: .forPreview)

    LibraryProfileSettingsView()
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(store)
        .environment(SupportStore())
        .environment(WhatsNewController(currentVersion: "1.54"))
}

/// Animates the expanding rows inside settings sections, on pushed pages and in the workspace alike.
fileprivate struct LibraryProfileSettingsContentAnimations: ViewModifier {
    let animation: Animation
    let episodeProgressTrackingEnabled: Bool
    let categoriesEnabled: Bool
    let categoryStripEnabled: Bool
    let libraryCloudSyncStatus: LibraryCloudSyncStatus

    func body(content: Content) -> some View {
        content
            .animation(animation, value: episodeProgressTrackingEnabled)
            .animation(animation, value: categoriesEnabled)
            .animation(animation, value: categoryStripEnabled)
            .animation(animation, value: libraryCloudSyncStatus)
    }
}
