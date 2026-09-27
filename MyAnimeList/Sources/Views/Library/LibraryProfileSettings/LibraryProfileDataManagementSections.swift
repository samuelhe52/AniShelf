//
//  LibraryProfileDataManagementSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import LibrarySync
import SwiftUI

struct LibraryProfileICloudSyncSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showRestorationDetails = false
    @State private var showSyncIssues = false

    let libraryCloudSyncStatus: LibraryCloudSyncStatus
    let cloudSyncToggleBinding: Binding<Bool>
    let cloudSyncToggleDisabled: Bool
    let cloudSyncToggleSubtitle: LocalizedStringResource
    let cloudSyncIsBusy: Bool
    let cloudSyncStatusTitleColor: Color
    let cloudSyncManualRetryDisabled: Bool
    let onRetryLibraryCloudSync: () -> Void
    let onDiscardFailedEntry: (LibraryCloudSyncFailedEntry) -> Void

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
                cloudSyncStatusRow
            }
        }
        .animation(.default, value: cloudSyncIsBusy)
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .indigo)
        .sheet(isPresented: $showSyncIssues) {
            LibraryCloudSyncIssuesSheet(
                issues: syncIssues,
                cloudSyncIsBusy: cloudSyncIsBusy,
                onDiscard: onDiscardFailedEntry
            )
        }
        .onChange(of: syncIssues.isEmpty) { _, isEmpty in
            if isEmpty { showSyncIssues = false }
        }
    }

    /// Problems a completed sync left behind.
    ///
    /// Restoration failures are shown separately.
    private var syncIssues: [LibraryCloudSyncIssue] {
        guard libraryCloudSyncStatus.isEnabled else { return [] }
        var issues: [LibraryCloudSyncIssue] = []
        let pendingFailures = libraryCloudSyncStatus.currentPendingReconstructionFailures
        if libraryCloudSyncStatus.restoration == nil, !pendingFailures.isEmpty {
            issues.append(.unloadedEntries(pendingFailures.map(LibraryCloudSyncFailedEntry.init)))
        }
        if libraryCloudSyncStatus.rejectedUploadCount > 0 {
            issues.append(.rejectedUploads(libraryCloudSyncStatus.rejectedUploadCount))
        }
        if libraryCloudSyncStatus.quarantinedRecordCount > 0 {
            issues.append(.unreadableRecords(libraryCloudSyncStatus.quarantinedRecordCount))
        }
        return issues
    }

    /// One issue is named directly; several fold into a single count.
    private var syncIssuesRow: some View {
        let issues = syncIssues
        let title: LocalizedStringResource =
            issues.count == 1
            ? issues[0].summary : "\(issues.reduce(0) { $0 + $1.count }) sync issues"
        return Button {
            showSyncIssues = true
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func failedEntriesInfoButton(
        isPresented: Binding<Bool>,
        title: LocalizedStringResource,
        message: String?,
        entries: [LibraryCloudSyncFailedEntry]
    ) -> some View {
        Button {
            isPresented.wrappedValue = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringResource("Review entries")))
        .popover(isPresented: isPresented) {
            LibraryFailedEntriesPopover(
                title: title,
                message: message,
                entries: entries,
                cloudSyncIsBusy: cloudSyncIsBusy,
                onDiscard: onDiscardFailedEntry
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var cloudSyncStatusRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            cloudSyncStatusAndRetryRow

            // Full width, so the issue line doesn't wrap beside the retry button.
            if !syncIssues.isEmpty {
                syncIssuesRow
            }
        }
        .animation(.default, value: syncIssues.map(\.count))
        .padding(.top, 4)
        .padding(.vertical, 1)
    }

    private var cloudSyncStatusAndRetryRow: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(libraryCloudSyncStatus.statusDisplay.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cloudSyncStatusTitleColor)

                if let restoration = libraryCloudSyncStatus.restoration {
                    HStack(spacing: 2) {
                        Text("Restored \(restoration.restoredEntries) of \(restoration.totalEntries) entries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !restoration.failures.isEmpty {
                            failedEntriesInfoButton(
                                isPresented: $showRestorationDetails,
                                title: "Entries needing retry",
                                message: libraryCloudSyncStatus.failureReasonDisplay,
                                entries: restoration.failures.map(LibraryCloudSyncFailedEntry.init)
                            )
                        }
                    }
                } else {
                    Text(libraryCloudSyncStatus.detailDisplayResource)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if libraryCloudSyncStatus.restoration?.failures.isEmpty != false,
                    let failureReason = libraryCloudSyncStatus.failureReasonDisplay
                {
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
    }
}

/// A failed iCloud entry the user can review, and discard when eligible.
struct LibraryCloudSyncFailedEntry: Identifiable {
    enum Source {
        case restoration(LibraryRestorationFailure)
        case pendingReconstruction(LibraryPendingReconstructionState.Failure)
    }

    enum DiscardState {
        case unavailable
        case available
        case pending
    }

    let source: Source
    let snapshot: LibraryEntrySyncSnapshot
    let reason: String
    let discardState: DiscardState

    var id: String { snapshot.identity.rawID }

    init(_ failure: LibraryRestorationFailure) {
        source = .restoration(failure)
        snapshot = failure.snapshot
        reason = failure.reason
        discardState =
            failure.discardDate != nil
            ? .pending : failure.canDiscard(at: .now) ? .available : .unavailable
    }

    init(_ failure: LibraryPendingReconstructionState.Failure) {
        source = .pendingReconstruction(failure)
        snapshot = failure.snapshot
        reason = failure.reason
        discardState =
            failure.discardDate != nil
            ? .pending : failure.canDiscard ? .available : .unavailable
    }
}

/// A problem a completed sync left behind.
fileprivate enum LibraryCloudSyncIssue: Identifiable {
    case unloadedEntries([LibraryCloudSyncFailedEntry])
    case rejectedUploads(Int)
    case unreadableRecords(Int)

    var id: String {
        switch self {
        case .unloadedEntries: "unloadedEntries"
        case .rejectedUploads: "rejectedUploads"
        case .unreadableRecords: "unreadableRecords"
        }
    }

    var count: Int {
        switch self {
        case .unloadedEntries(let entries): entries.count
        case .rejectedUploads(let count), .unreadableRecords(let count): count
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .unloadedEntries(let entries): "\(entries.count) entries not loaded"
        case .rejectedUploads(let count): "\(count) changes not uploaded"
        case .unreadableRecords(let count): "\(count) unreadable records"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .unloadedEntries:
            "Entries TMDb no longer lists can be discarded from iCloud. Others retry automatically."
        case .rejectedUploads:
            "iCloud didn't accept these changes. They stay saved on this device, and AniShelf tries uploading them again on later syncs."
        case .unreadableRecords:
            "AniShelf couldn't read these records. They may have been saved by a newer version of the app. They stay untouched in iCloud, and this device won't overwrite them. Updating AniShelf may resolve this."
        }
    }
}

fileprivate struct LibraryCloudSyncIssuesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let issues: [LibraryCloudSyncIssue]
    let cloudSyncIsBusy: Bool
    let onDiscard: (LibraryCloudSyncFailedEntry) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(issues) { issue in
                        issueSection(issue)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .animation(.default, value: issues.map(\.id))
                .animation(.default, value: issues.map(\.count))
                .padding(20)
            }
            .preferredNavigationBarScrollEdgeEffect()
            .navigationTitle("Sync Issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func issueSection(_ issue: LibraryCloudSyncIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
            Text(issue.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .unloadedEntries(let entries) = issue {
                Divider()
                    .padding(.vertical, 6)
                LibraryFailedEntriesList(
                    entries: entries,
                    animatesChanges: true,
                    cloudSyncIsBusy: cloudSyncIsBusy,
                    onDiscard: onDiscard
                )
                .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

fileprivate struct LibraryFailedEntriesPopover: View {
    let title: LocalizedStringResource
    let message: String?
    let entries: [LibraryCloudSyncFailedEntry]
    let cloudSyncIsBusy: Bool
    let onDiscard: (LibraryCloudSyncFailedEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Keep all content changes immediate while the popover resizes.
                LibraryFailedEntriesList(
                    entries: entries,
                    animatesChanges: false,
                    cloudSyncIsBusy: cloudSyncIsBusy,
                    onDiscard: onDiscard
                )
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: 300)
        .frame(maxHeight: 360)
        .transaction { $0.animation = nil }
    }
}

/// Failed entries with TMDb links and discard actions.
///
/// Inherits its font from the container. The sheet animates changes; the
/// popover updates immediately to avoid animating its size.
fileprivate struct LibraryFailedEntriesList: View {
    let entries: [LibraryCloudSyncFailedEntry]
    let animatesChanges: Bool
    let cloudSyncIsBusy: Bool
    let onDiscard: (LibraryCloudSyncFailedEntry) -> Void

    @State private var discardCandidate: LibraryCloudSyncFailedEntry?
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    if entry.id != entries.first?.id {
                        Divider()
                    }
                    entryRow(entry)
                }
                .transition(animatesChanges ? .opacity : .identity)
            }
        }
        .animation(animatesChanges ? .default : nil, value: entries.map(\.id))
        .alert("Discard Entry from iCloud?", isPresented: $showDiscardConfirmation) {
            Button("Discard from iCloud", role: .destructive) {
                if let discardCandidate { onDiscard(discardCandidate) }
                discardCandidate = nil
            }
            Button("Cancel", role: .cancel) { discardCandidate = nil }
        } message: {
            Text(
                "This deletes \(discardCandidate?.id ?? "") and its saved tracking data from your iCloud library. The deletion will sync to your other devices."
            )
        }
    }

    private func entryRow(_ entry: LibraryCloudSyncFailedEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(destination: tmdbURL(for: entry)) {
                HStack(spacing: 4) {
                    Text(entryTypeTitle(for: entry))
                    Text(verbatim: "· TMDb \(entry.snapshot.tmdbID)")
                    Image(systemName: "arrow.up.right")
                        .imageScale(.small)
                }
                .fontWeight(.semibold)
            }
            Text(entry.reason)
                .foregroundStyle(.secondary)
            discardControl(for: entry)
                .transition(animatesChanges ? .opacity : .identity)
        }
        .animation(animatesChanges ? .default : nil, value: entry.discardState)
        .animation(animatesChanges ? .default : nil, value: entry.reason)
    }

    @ViewBuilder
    private func discardControl(for entry: LibraryCloudSyncFailedEntry) -> some View {
        switch entry.discardState {
        case .pending:
            Text("Deletion pending. Retry to finish.")
        case .available:
            Button("Discard from iCloud…", role: .destructive) {
                discardCandidate = entry
                showDiscardConfirmation = true
            }
            .fontWeight(.semibold)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(cloudSyncIsBusy)
        case .unavailable:
            EmptyView()
        }
    }

    private func tmdbURL(for failure: LibraryCloudSyncFailedEntry) -> URL {
        let path: String
        switch failure.snapshot.entryType {
        case .movie:
            path = "movie/\(failure.snapshot.tmdbID)"
        case .series:
            path = "tv/\(failure.snapshot.tmdbID)"
        case .season(let seasonNumber, let parentSeriesID):
            path = "tv/\(parentSeriesID)/season/\(seasonNumber)"
        }
        return URL(string: "https://www.themoviedb.org/\(path)")!
    }

    private func entryTypeTitle(for failure: LibraryCloudSyncFailedEntry) -> LocalizedStringResource {
        switch failure.snapshot.entryType {
        case .movie:
            "Movie"
        case .series:
            "TV Series"
        case .season(let seasonNumber, parentSeriesID: _):
            "Season \(seasonNumber)"
        }
    }
}

struct LibraryProfileBackupExportSection: View {
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
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .cyan, filled: false))
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
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .orange, filled: false))
    }
}

struct LibraryProfileMaintenanceActionsSection: View {
    let onChangeAPIKey: () -> Void
    let onCheckMetadataCacheSize: () -> Void
    let onRefreshInfos: () -> Void
    let onPrefetchImages: () -> Void
    let showRebuildLibraryCloudSync: Bool
    let rebuildLibraryCloudSyncDisabled: Bool
    let onRequestRebuildLibraryCloudSync: () -> Void
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
                tint: LibraryProfileMaintenancePalette.accent,
                action: onChangeAPIKey
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Check Metadata Cache Size",
                subtitle: "Review image and metadata cache usage.",
                systemImage: "archivebox",
                tint: LibraryProfileMaintenancePalette.accent,
                action: onCheckMetadataCacheSize
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Refresh Infos",
                subtitle: "Fetch latest TMDb metadata for every entry.",
                systemImage: "arrow.clockwise",
                tint: LibraryProfileMaintenancePalette.accent,
                action: onRefreshInfos
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Prefetch Images",
                subtitle: "Cache posters and artwork without refreshing metadata.",
                systemImage: "photo.stack",
                tint: LibraryProfileMaintenancePalette.accent,
                action: onPrefetchImages
            )
            LibraryProfileActionDivider()
            if showRebuildLibraryCloudSync {
                LibraryProfileActionRow(
                    title: "Rebuild iCloud Sync",
                    subtitle: "Refetch and reconcile your iCloud library with your local library.",
                    systemImage: "arrow.triangle.2.circlepath.icloud",
                    tint: LibraryProfileMaintenancePalette.accent,
                    action: onRequestRebuildLibraryCloudSync
                )
                .disabled(rebuildLibraryCloudSyncDisabled)
                .opacity(rebuildLibraryCloudSyncDisabled ? 0.52 : 1)
                LibraryProfileActionDivider()
            }
            if let whatsNewVersion {
                LibraryProfileActionRow(
                    title: "What's New",
                    subtitle: whatsNewSubtitleResource(for: whatsNewVersion),
                    systemImage: "sparkles.rectangle.stack",
                    tint: LibraryProfileMaintenancePalette.accent,
                    action: onShowWhatsNew
                )
                LibraryProfileActionDivider()
            }
            LibraryProfileActionRow(
                title: "Support AniShelf",
                subtitle: "Optional tip jar. No features are unlocked.",
                systemImage: "heart.circle",
                tint: LibraryProfileMaintenancePalette.accent,
                action: onShowSupport
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "About AniShelf",
                subtitle: "Version, links, and credits.",
                systemImage: "info.circle",
                tint: LibraryProfileMaintenancePalette.accent,
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
