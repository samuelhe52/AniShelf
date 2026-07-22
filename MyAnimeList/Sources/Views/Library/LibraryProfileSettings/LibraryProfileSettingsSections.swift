//
//  LibraryProfileSettingsSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/3.
//

import DataProvider
import SwiftUI

struct LibraryProfileHeroCard: View {
    let stats: LibraryProfileStats
    let animeTitleResource: LocalizedStringResource

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image(.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.orange.gradient, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.7), lineWidth: 1)
                    }
                    .offset(x: 6, y: 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(stats.totalCount)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(animeTitleResource)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .popupGlassPanel(cornerRadius: 30, tint: .white.opacity(0.045))
    }
}

struct LibraryProfilePrimaryStatsGrid: View {
    enum Layout {
        case compact
        case fillsSummaryHeight
    }

    let stats: LibraryProfileStats
    let layout: Layout

    @ViewBuilder
    var body: some View {
        switch layout {
        case .compact:
            compactGrid
        case .fillsSummaryHeight:
            expandedGrid
        }
    }

    private var compactGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            watchedMetric
            watchingMetric
            favoriteMetric
            plannedMetric
        }
    }

    private var expandedGrid: some View {
        VStack(spacing: 12) {
            metricRow(watchedMetric, watchingMetric)
            metricRow(favoriteMetric, plannedMetric)
        }
        .frame(maxHeight: .infinity)
    }

    private var watchedMetric: some View {
        LibraryProfileMetricCard(
            title: "Watched",
            value: stats.watchedCount,
            systemImage: "checkmark.circle.fill",
            tint: AnimeEntry.WatchStatus.watched.libraryTintColor,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private var watchingMetric: some View {
        LibraryProfileMetricCard(
            title: "Watching",
            value: stats.watchingCount,
            systemImage: "play.circle.fill",
            tint: AnimeEntry.WatchStatus.watching.libraryTintColor,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private var favoriteMetric: some View {
        LibraryProfileMetricCard(
            title: "Favorites",
            value: stats.favoriteCount,
            systemImage: "heart.fill",
            tint: .pink,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private var plannedMetric: some View {
        LibraryProfileMetricCard(
            title: "Planned",
            value: stats.planToWatchCount,
            systemImage: "bookmark.fill",
            tint: AnimeEntry.WatchStatus.planToWatch.libraryTintColor,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private func metricRow<Leading: View, Trailing: View>(
        _ leading: Leading,
        _ trailing: Trailing
    ) -> some View {
        HStack(spacing: 12) {
            leading
                .frame(maxWidth: .infinity, alignment: .topLeading)
            trailing
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private var fillsAvailableHeight: Bool {
        switch layout {
        case .compact:
            false
        case .fillsSummaryHeight:
            true
        }
    }
}

struct LibraryProfileLibraryDetailsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var runtimeMode: LibraryProfileRuntimeMode = .total

    let stats: LibraryProfileStats

    var body: some View {
        PopupSectionCard(
            "Library Details",
            systemImage: "sparkles.rectangle.stack",
            spacing: 14,
            panelTint: sectionCardTint
        ) {
            VStack(spacing: 10) {
                LibraryProfileDetailRow(title: "Movies", value: "\(stats.movieCount)", systemImage: "film")
                LibraryProfileDetailRow(title: "Series", value: "\(stats.seriesCount)", systemImage: "tv")
                LibraryProfileDetailRow(
                    title: "Seasons",
                    value: "\(stats.seasonCount)",
                    systemImage: "square.stack.3d.up"
                )
                LibraryProfileDetailRow(
                    title: "With Notes",
                    value: "\(stats.entriesWithNotesCount)",
                    systemImage: "note.text"
                )
                LibraryProfileDetailRow(
                    title: runtimeMode.title,
                    value: runtimeMode.description(for: stats),
                    systemImage: "clock"
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: cycleRuntimeMode)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(runtimeMode.accessibilityHint))
            }
        }
    }

    private var sectionCardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }

    private func cycleRuntimeMode() {
        withAnimation {
            runtimeMode.advance()
        }
    }
}

struct LibraryProfileSettingsCard: View {
    enum Layout {
        case compactCard
        case workspaceGrid
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cloudSyncActionInFlight = false
    @State private var showCloudSyncConflictAlert = false
    @State private var showRestoreUnavailableAlert = false

    @Binding var followsSystemLanguage: Bool
    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>
    @Binding var openDetailWithSingleTap: Bool
    @Binding var entryDetailCharactersExpandedByDefault: Bool
    @Binding var entryDetailStaffExpandedByDefault: Bool
    @Binding var scoringEnabled: Bool
    @Binding var episodeProgressTrackingEnabled: Bool
    @Binding var posterProgressBarOverlayEnabled: Bool
    @Binding var autoPrefetchImagesOnAddAndRestore: Bool
    @Binding var longTermGalleryPosterCachingEnabled: Bool
    @Binding var useTMDbRelayServer: Bool
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
        defaultSettingsSection
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

    private var defaultSettingsSection: some View {
        LibraryProfileDefaultSettingsSection(
            hideDroppedByDefault: $hideDroppedByDefault,
            defaultNewEntryWatchStatus: $defaultNewEntryWatchStatus,
            defaultFilters: $defaultFilters,
            openDetailWithSingleTap: $openDetailWithSingleTap,
            entryDetailCharactersExpandedByDefault: $entryDetailCharactersExpandedByDefault,
            entryDetailStaffExpandedByDefault: $entryDetailStaffExpandedByDefault,
            scoringEnabled: $scoringEnabled,
            episodeProgressTrackingEnabled: $episodeProgressTrackingEnabled,
            posterProgressBarOverlayEnabled: $posterProgressBarOverlayEnabled,
            autoPrefetchImagesOnAddAndRestore: $autoPrefetchImagesOnAddAndRestore,
            longTermGalleryPosterCachingEnabled: $longTermGalleryPosterCachingEnabled
        )
    }

    private var tmdbConnectionSection: some View {
        LibraryProfileTMDbConnectionSection(useTMDbRelayServer: $useTMDbRelayServer)
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
                defaultSettingsSection
                tmdbConnectionSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(spacing: 20) {
                iCloudSyncSection
                backupExportSection
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
        cloudSyncActionInFlight
            || libraryCloudSyncStatus.bootstrapState == .running
            || libraryCloudSyncStatus.hasActiveSyncPhase
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

fileprivate struct LibraryProfileLanguageSettingsSection: View {
    @Binding var followsSystemLanguage: Bool
    @Binding var preferredLanguage: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Anime Info Language",
                subtitle: "Choose the language used for future metadata fetches.",
                systemImage: "globe",
                tint: .blue
            )

            HStack {
                Text("Follow System")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Toggle("Follow System", isOn: $followsSystemLanguage)
                    .labelsHidden()
                    .tint(.blue)
                    .scaleEffect(0.78, anchor: .trailing)
                    .frame(width: 42, height: 26, alignment: .trailing)
            }
            .padding(.vertical, 2)

            if !followsSystemLanguage {
                Picker("Anime Info Language", selection: $preferredLanguage) {
                    ForEach(Language.allCases, id: \.rawValue) { language in
                        Text(language.localizedStringResource).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 2)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .blue)
    }
}

fileprivate struct LibraryProfileDefaultSettingsSection: View {
    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>
    @Binding var openDetailWithSingleTap: Bool
    @Binding var entryDetailCharactersExpandedByDefault: Bool
    @Binding var entryDetailStaffExpandedByDefault: Bool
    @Binding var scoringEnabled: Bool
    @Binding var episodeProgressTrackingEnabled: Bool
    @Binding var posterProgressBarOverlayEnabled: Bool
    @Binding var autoPrefetchImagesOnAddAndRestore: Bool
    @Binding var longTermGalleryPosterCachingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Library Defaults",
                systemImage: "line.3.horizontal.decrease.circle",
                tint: .mint
            )

            defaultWatchStatusRow
            defaultFiltersRow

            LibraryProfileSettingsToggleRow(
                title: "Open Detail with Single Tap",
                subtitle: "By default, double tap opens detail. Turn this on to use single tap instead.",
                isOn: $openDetailWithSingleTap
            )

            LibraryProfileSettingsToggleRow(
                title: "Expand Characters by Default",
                subtitle: "Open the Characters section automatically in entry detail view.",
                isOn: $entryDetailCharactersExpandedByDefault
            )

            LibraryProfileSettingsToggleRow(
                title: "Expand Staff by Default",
                subtitle: "Open the Staff section automatically in entry detail view.",
                isOn: $entryDetailStaffExpandedByDefault
            )

            LibraryProfileSettingsToggleRow(
                title: "Enable Scoring",
                subtitle: "Turning this off does not delete previously saved scores.",
                isOn: $scoringEnabled
            )

            LibraryProfileSettingsToggleRow(
                title: "Track Episode Progress",
                subtitle: "Turning this off hides episode progress without deleting saved progress.",
                isOn: $episodeProgressTrackingEnabled
            )

            if episodeProgressTrackingEnabled {
                LibraryProfileSettingsToggleRow(
                    title: "Show Poster Progress Bar",
                    subtitle: "Show episode progress as a poster overlay in the library.",
                    isOn: $posterProgressBarOverlayEnabled
                )
            }

            LibraryProfileSettingsToggleRow(
                title: "Hide Dropped Entries",
                subtitle: "Only show dropped entries after you explicitly enable the Dropped filter.",
                isOn: $hideDroppedByDefault
            )

            LibraryProfileSettingsToggleRow(
                title: "Auto Prefetch Images",
                subtitle: "Prefetch images when adding titles or restoring a backup.",
                isOn: $autoPrefetchImagesOnAddAndRestore
            )

            LibraryProfileSettingsToggleRow(
                title: "Cache Large Gallery Posters",
                subtitle:
                    "Store large Gallery posters longer. Off by default and may use more disk space.",
                isOn: $longTermGalleryPosterCachingEnabled
            )
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .mint)
    }

    private var defaultWatchStatusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("New Entries Start As")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Menu {
                ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                    Button {
                        defaultNewEntryWatchStatus = status
                    } label: {
                        if status == defaultNewEntryWatchStatus {
                            Label(status.localizedStringResource, systemImage: "checkmark")
                        } else {
                            Text(status.localizedStringResource)
                        }
                    }
                }
            } label: {
                LibraryProfileSelectionCapsule(
                    title: defaultNewEntryWatchStatus.localizedStringResource,
                    tint: defaultNewEntryWatchStatus.defaultPickerTintColor
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var defaultFiltersRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Default Filters")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Menu {
                Toggle("All", isOn: allDefaultFiltersBinding)
                ForEach(LibraryStore.AnimeFilter.typeCases, id: \.self) { filter in
                    defaultFilterToggle(for: filter)
                }
                Menu("Watch Status") {
                    ForEach(LibraryStore.AnimeFilter.watchStatusCases, id: \.self) { filter in
                        defaultFilterToggle(for: filter)
                    }
                }
                defaultFilterToggle(for: .favorited)
            } label: {
                LibraryProfileSelectionCapsule(
                    title: defaultFiltersSummaryResource,
                    tint: .mint
                )
            }
            .menuActionDismissBehavior(.disabled)
        }
        .padding(.vertical, 2)
    }

    private var orderedDefaultFilters: [LibraryStore.AnimeFilter] {
        LibraryStore.AnimeFilter.allCases.filter { defaultFilters.contains($0) }
    }

    private var defaultFiltersSummaryResource: LocalizedStringResource {
        switch orderedDefaultFilters.count {
        case 0:
            return "All"
        case 1:
            return defaultFilterSummaryResource(for: orderedDefaultFilters[0])
        default:
            return "\(orderedDefaultFilters.count) Filters"
        }
    }

    private var allDefaultFiltersBinding: Binding<Bool> {
        .init(
            get: { defaultFilters.isEmpty },
            set: {
                if $0 {
                    defaultFilters.removeAll()
                }
            }
        )
    }

    private func defaultFilterBinding(for filter: LibraryStore.AnimeFilter) -> Binding<Bool> {
        .init(
            get: { defaultFilters.contains(filter) },
            set: {
                if $0 {
                    defaultFilters.insert(filter)
                } else {
                    defaultFilters.remove(filter)
                }
            }
        )
    }

    private func defaultFilterSummaryResource(
        for filter: LibraryStore.AnimeFilter
    ) -> LocalizedStringResource {
        switch filter.id {
        case LibraryStore.AnimeFilter.favorited.id:
            return "Favorites"
        case LibraryStore.AnimeFilter.watched.id:
            return "Watched"
        case LibraryStore.AnimeFilter.planToWatch.id:
            return "Planned"
        case LibraryStore.AnimeFilter.watching.id:
            return "Watching"
        case LibraryStore.AnimeFilter.dropped.id:
            return "Dropped"
        default:
            return filter.name
        }
    }

    @ViewBuilder
    private func defaultFilterToggle(for filter: LibraryStore.AnimeFilter) -> some View {
        Toggle(
            isOn: defaultFilterBinding(for: filter),
            label: { Text(filter.name) }
        )
    }
}

fileprivate struct LibraryProfileTMDbConnectionSection: View {
    @Binding var useTMDbRelayServer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "TMDb Connection",
                subtitle: "Turn this on if direct TMDb access is unstable on your network.",
                systemImage: "network",
                tint: .cyan
            )

            LibraryProfileSettingsToggleRow(
                title: "Use TMDb Proxy",
                subtitle: "Turn this off if you use a VPN or another proxy.",
                isOn: $useTMDbRelayServer,
                tint: .cyan
            )
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .cyan)
    }
}

fileprivate struct LibraryProfileICloudSyncSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let libraryCloudSyncStatus: LibraryCloudSyncStatus
    let cloudSyncToggleBinding: Binding<Bool>
    let cloudSyncToggleDisabled: Bool
    let cloudSyncToggleSubtitle: LocalizedStringResource
    let cloudSyncIsBusy: Bool
    let cloudSyncStatusTitleColor: Color
    let cloudSyncManualRetryDisabled: Bool
    let onRetryLibraryCloudSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "iCloud Sync",
                subtitle: "Keep your library available across devices.",
                systemImage: "icloud",
                tint: .indigo
            )

            LibraryProfileSettingsToggleRow(
                title: "Master Switch",
                subtitle: cloudSyncToggleSubtitle,
                isOn: cloudSyncToggleBinding,
                tint: .indigo
            )
            .disabled(cloudSyncToggleDisabled)

            if libraryCloudSyncStatus.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    cloudSyncStatusRow
                }
            }
        }
        .animation(.default, value: cloudSyncIsBusy)
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .indigo)
    }

    private var cloudSyncStatusRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(libraryCloudSyncStatus.statusDisplay.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cloudSyncStatusTitleColor)

                Text(libraryCloudSyncStatus.detailDisplayResource)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let failureReason = libraryCloudSyncStatus.failureReasonDisplay {
                    Text(failureReason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 10)

            Button(action: onRetryLibraryCloudSync) {
                Label(libraryCloudSyncStatus.actionTitleResource, systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo.opacity(colorScheme == .dark ? 0.92 : 0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background {
                Capsule(style: .continuous)
                    .fill(.indigo.opacity(colorScheme == .dark ? 0.12 : 0.07))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.indigo.opacity(0.14), lineWidth: 1)
            }
            .padding(.top, 4)
            .disabled(cloudSyncManualRetryDisabled)
            .opacity(cloudSyncManualRetryDisabled ? 0.52 : 1)
        }
        .padding(.top, 4)
        .padding(.vertical, 1)
    }
}

fileprivate struct LibraryProfileBackupExportSection: View {
    let libraryCloudSyncStatus: LibraryCloudSyncStatus
    let restoreCompleted: Bool
    let createBackupItems: () -> [Any]?
    let onExportLibrary: (LibraryExportFormat) -> Void
    let onRestoreButtonPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryProfileSettingHeader(
                title: "Backup & Restore",
                subtitle:
                    "App backups keep AniShelf data and settings for restore. Library exports create user-facing files in standard formats.",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: .orange
            )

            HStack(spacing: 10) {
                backupButton
                    .frame(maxWidth: .infinity)
                restoreButton
                    .frame(maxWidth: .infinity)
            }
            .disabled(restoreCompleted)

            if restoreCompleted {
                HStack {
                    Spacer()
                    Text("Restore completed!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                    Spacer()
                }
            }

            libraryExportMenu

            Text("* For security reasons, your TMDb API Key will not be exported.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .orange)
    }

    @ViewBuilder
    private var backupButton: some View {
        LazyShareLink(prepareData: createBackupItems) {
            Label("Backup", systemImage: "archivebox")
        }
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .blue, filled: false))
    }

    private var restoreButton: some View {
        Button(role: .destructive, action: onRestoreButtonPress) {
            Label("Restore", systemImage: restoreButtonSystemImage)
        }
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .red, filled: false))
        .opacity(libraryCloudSyncStatus.blocksBackupRestore ? 0.52 : 1)
        .accessibilityHint(Text(restoreButtonAccessibilityHint))
    }

    private var restoreButtonSystemImage: String {
        libraryCloudSyncStatus.blocksBackupRestore ? "icloud.slash" : "document.badge.clock"
    }

    private var restoreButtonAccessibilityHint: LocalizedStringResource {
        if libraryCloudSyncStatus.blocksBackupRestore {
            "Turn off iCloud Sync before restoring a backup. You can turn it on again after restore."
        } else {
            "Restore a library backup."
        }
    }

    private var libraryExportMenu: some View {
        Menu {
            ForEach(LibraryExportFormat.allCases) { format in
                Button {
                    onExportLibrary(format)
                } label: {
                    Label(format.menuTitleResource, systemImage: format.menuSystemImage)
                }
            }
        } label: {
            Label("Export as...", systemImage: "square.and.arrow.up.on.square")
        }
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .teal, filled: false))
    }
}

fileprivate struct LibraryProfileMaintenanceActionsSection: View {
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
        VStack(spacing: 0) {
            LibraryProfileActionRow(
                title: "Change API Key",
                subtitle: "Update the TMDb key used for metadata.",
                systemImage: "person.badge.key",
                tint: LibraryProfileMaintenancePalette.apiKey,
                action: onChangeAPIKey
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Check Metadata Cache Size",
                subtitle: "Review image and metadata cache usage.",
                systemImage: "archivebox",
                tint: LibraryProfileMaintenancePalette.cache,
                action: onCheckMetadataCacheSize
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Refresh Infos",
                subtitle: "Fetch latest TMDb metadata for every entry.",
                systemImage: "arrow.clockwise",
                tint: LibraryProfileMaintenancePalette.refresh,
                action: onRefreshInfos
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Prefetch Images",
                subtitle: "Cache posters and artwork without refreshing metadata.",
                systemImage: "photo.stack",
                tint: LibraryProfileMaintenancePalette.prefetch,
                action: onPrefetchImages
            )
            LibraryProfileActionDivider()
            if let whatsNewVersion {
                LibraryProfileActionRow(
                    title: "What's New",
                    subtitle: whatsNewSubtitleResource(for: whatsNewVersion),
                    systemImage: "sparkles.rectangle.stack",
                    tint: LibraryProfileMaintenancePalette.whatsNew,
                    action: onShowWhatsNew
                )
                LibraryProfileActionDivider()
            }
            LibraryProfileActionRow(
                title: "Support AniShelf",
                subtitle: "Optional tip jar. No features are unlocked.",
                systemImage: "heart.circle",
                tint: LibraryProfileMaintenancePalette.support,
                action: onShowSupport
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "About AniShelf",
                subtitle: "Version, links, and credits.",
                systemImage: "info.circle",
                tint: LibraryProfileMaintenancePalette.about,
                action: onShowAbout
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Delete All Animes",
                subtitle: "Remove every saved library entry.",
                systemImage: "trash",
                role: .destructive,
                tint: .red,
                action: onDeleteAllAnimes
            )
        }
        .padding(.vertical, 4)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileMaintenancePalette.panel)
    }

    private func whatsNewSubtitleResource(for version: String) -> LocalizedStringResource {
        "Reopen the release note for version \(version)."
    }
}

fileprivate struct LibraryProfileSettingsToggleRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    @Binding var isOn: Bool
    var tint: Color = .mint

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(tint)
                .scaleEffect(0.78, anchor: .trailing)
                .frame(width: 42, height: 26, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

extension LibraryCloudSyncStatus {
    fileprivate struct DisplayStatus {
        let title: LocalizedStringResource
        let systemImage: String
        let tint: Color
    }

    fileprivate var hasActiveSyncPhase: Bool {
        bootstrapState == .completed && currentPhase != nil && lastResult == nil
    }

    fileprivate var isFailureDisplay: Bool {
        if bootstrapState == .failed {
            return true
        }
        switch lastResult {
        case .retryableFailure, .permanentFailure:
            return true
        case .success, .skipped, .conflictChoiceRequired, nil:
            return false
        }
    }

    fileprivate var statusDisplay: DisplayStatus {
        if bootstrapState == .running {
            return DisplayStatus(title: "Preparing iCloud", systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
        }
        if hasActiveSyncPhase {
            return DisplayStatus(title: "Syncing", systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
        }

        switch bootstrapState {
        case .notStarted:
            return DisplayStatus(title: "Ready to Sync", systemImage: "icloud", tint: .indigo)
        case .needsConflictChoice:
            return DisplayStatus(title: "Needs Choice", systemImage: "exclamationmark.triangle", tint: .orange)
        case .running:
            return DisplayStatus(title: "Preparing iCloud", systemImage: "arrow.triangle.2.circlepath", tint: .indigo)
        case .completed:
            switch lastResult {
            case .success:
                return DisplayStatus(title: "Synced", systemImage: "checkmark.icloud", tint: .green)
            case .skipped:
                return DisplayStatus(title: "Sync Skipped", systemImage: "pause.circle", tint: .secondary)
            case .retryableFailure, .permanentFailure:
                return DisplayStatus(title: "Sync Failed", systemImage: "xmark.icloud", tint: .red)
            case .conflictChoiceRequired:
                return DisplayStatus(title: "Needs Choice", systemImage: "exclamationmark.triangle", tint: .orange)
            case nil:
                return DisplayStatus(title: "Sync Enabled", systemImage: "icloud", tint: .indigo)
            }
        case .failed:
            return DisplayStatus(title: "Setup Failed", systemImage: "xmark.icloud", tint: .red)
        }
    }

    fileprivate var detailDisplayResource: LocalizedStringResource {
        if bootstrapState == .needsConflictChoice || lastResult == .conflictChoiceRequired {
            return conflictSummaryResource
        }
        if isFailureDisplay {
            if let lastAttemptDate {
                return "Last attempt: \(lastAttemptDate.libraryCloudSyncRelativeDescription)"
            }
            return "No sync yet."
        }
        if let lastSuccessfulSyncDate {
            return "Last sync: \(lastSuccessfulSyncDate.libraryCloudSyncRelativeDescription)"
        } else if let lastAttemptDate {
            return "Last attempt: \(lastAttemptDate.libraryCloudSyncRelativeDescription)"
        } else {
            return "No sync yet."
        }
    }

    fileprivate var failureReasonDisplay: String? {
        guard isFailureDisplay, let lastFailureReason, !lastFailureReason.isEmpty else {
            return nil
        }
        return lastFailureReason
    }

    fileprivate var actionTitleResource: LocalizedStringResource {
        isFailureDisplay ? "Retry" : "Sync Now"
    }

    fileprivate var conflictSummaryResource: LocalizedStringResource {
        guard let summary = pendingConflictSummary else {
            return "Choose which library data to keep."
        }
        return
            "\(summary.entryCount) entries. Library: \(summary.libraryDomainCount), tracking: \(summary.trackingDomainCount), episodes: \(summary.episodeProgressDomainCount)."
    }
}

extension Date {
    fileprivate var libraryCloudSyncRelativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension LibraryExportFormat {
    fileprivate var menuTitleResource: LocalizedStringResource {
        switch self {
        case .plainText:
            "Plain Text (.txt)"
        case .csv:
            "Comma-Separated Values (.csv)"
        case .tsv:
            "Tab-Separated Values (.tsv)"
        case .json:
            "JSON (.json)"
        case .excel:
            "Excel Workbook (.xlsx)"
        }
    }

    fileprivate var menuSystemImage: String {
        switch self {
        case .plainText:
            "doc.plaintext"
        case .csv:
            "tablecells"
        case .tsv:
            "tablecells.badge.ellipsis"
        case .json:
            "curlybraces"
        case .excel:
            "tablecells.fill"
        }
    }
}
