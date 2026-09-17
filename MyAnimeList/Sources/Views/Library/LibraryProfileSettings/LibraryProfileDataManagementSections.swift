//
//  LibraryProfileDataManagementSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

struct LibraryProfileICloudSyncSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showRestorationDetails = false

    let libraryCloudSyncStatus: LibraryCloudSyncStatus
    let cloudSyncToggleBinding: Binding<Bool>
    let cloudSyncToggleDisabled: Bool
    let cloudSyncToggleSubtitle: LocalizedStringResource
    let cloudSyncIsBusy: Bool
    let cloudSyncStatusTitleColor: Color
    let cloudSyncManualRetryDisabled: Bool
    let onRetryLibraryCloudSync: () -> Void
    let onDiscardFailedRestorationEntry: (LibraryRestorationFailure) -> Void

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

    }

    private var restorationInfoButton: some View {
        Button {
            showRestorationDetails = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringResource("Review entries")))
        .popover(isPresented: $showRestorationDetails) {
            LibraryRestorationDetailsPopover(
                failures: libraryCloudSyncStatus.restoration?.failures ?? [],
                failureReason: libraryCloudSyncStatus.failureReasonDisplay,
                cloudSyncIsBusy: cloudSyncIsBusy,
                onDiscard: onDiscardFailedRestorationEntry
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var cloudSyncStatusRow: some View {
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
                            restorationInfoButton
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
        .padding(.top, 4)
        .padding(.vertical, 1)
    }
}

fileprivate struct LibraryRestorationDetailsPopover: View {
    let failures: [LibraryRestorationFailure]
    let failureReason: String?
    let cloudSyncIsBusy: Bool
    let onDiscard: (LibraryRestorationFailure) -> Void

    @State private var discardCandidate: LibraryRestorationFailure?
    @State private var showDiscardConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringResource("Entries needing retry"))
                    .font(.callout.weight(.semibold))
                if let failureReason {
                    Text(failureReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(failures) { failure in
                    VStack(alignment: .leading, spacing: 6) {
                        Link(destination: tmdbURL(for: failure)) {
                            HStack(spacing: 4) {
                                Text(entryTypeTitle(for: failure))
                                Text(verbatim: "· TMDb \(failure.snapshot.tmdbID)")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.semibold))
                            }
                            .font(.caption.weight(.semibold))
                        }
                        Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                        if failure.discardDate != nil {
                            Text("Deletion pending. Retry to finish.").font(.caption)
                        } else if failure.canDiscard(at: .now) {
                            Button("Discard from iCloud…", role: .destructive) {
                                discardCandidate = failure
                                showDiscardConfirmation = true
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .disabled(cloudSyncIsBusy)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
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
        .frame(width: 300)
        .frame(maxHeight: 360)
    }

    private func tmdbURL(for failure: LibraryRestorationFailure) -> URL {
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

    private func entryTypeTitle(for failure: LibraryRestorationFailure) -> LocalizedStringResource {
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
