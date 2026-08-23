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

    let libraryCloudSyncStatus: LibraryCloudSyncStatus
    let cloudSyncToggleBinding: Binding<Bool>
    let cloudSyncToggleDisabled: Bool
    let cloudSyncToggleSubtitle: LocalizedStringResource
    let cloudSyncIsBusy: Bool
    let cloudSyncStatusTitleColor: Color
    let cloudSyncManualRetryDisabled: Bool
    let cloudSyncRebuildDisabled: Bool
    let onRetryLibraryCloudSync: () -> Void
    let onRequestRebuildLibraryCloudSync: () -> Void

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
                    rebuildCloudSyncButton
                }
            }
        }
        .animation(.default, value: cloudSyncIsBusy)
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .indigo)
    }

    private var rebuildCloudSyncButton: some View {
        Button(action: onRequestRebuildLibraryCloudSync) {
            Label("Rebuild iCloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .indigo, filled: false))
        .disabled(cloudSyncRebuildDisabled)
        .opacity(cloudSyncRebuildDisabled ? 0.52 : 1)
        .accessibilityHint(
            Text("Refetch and reconcile your iCloud library with your local library.")
        )
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
