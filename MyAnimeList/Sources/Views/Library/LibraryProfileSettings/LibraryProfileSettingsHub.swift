//
//  LibraryProfileSettingsHub.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/13.
//

import DataProvider
import SwiftUI

struct LibraryProfileSettingsHub: View {
    @Environment(\.colorScheme) private var colorScheme
    let languageSummary: LocalizedStringResource
    let remindersLoaded: Bool
    let syncStatus: LibraryCloudSyncStatus
    let whatsNewVersion: String?
    let onShowWhatsNew: () -> Void
    let onShowSupport: () -> Void
    let onShowAbout: () -> Void
    private let reminders = AiringReminderCoordinator.shared

    var body: some View {
        VStack(spacing: 16) {
            PopupSectionCard("Settings", systemImage: "gearshape.2", spacing: 8, panelTint: cardTint) {
                VStack(spacing: 0) {
                    ForEach(LibraryProfileSettingsDestination.allCases, id: \.self) { destination in
                        if destination != LibraryProfileSettingsDestination.allCases.first {
                            LibraryProfileActionDivider(leadingInset: 44)
                        }
                        NavigationLink(value: destination) {
                            row(destination)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LibraryProfileAppInfoCard(
                whatsNewVersion: whatsNewVersion, onShowWhatsNew: onShowWhatsNew,
                onShowSupport: onShowSupport, onShowAbout: onShowAbout
            )
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }

    @ViewBuilder
    private func row(_ destination: LibraryProfileSettingsDestination) -> some View {
        switch destination {
        case .language:
            LibraryProfileHubRow(
                title: destination.title, systemImage: "globe", tint: destination.tint, value: languageSummary)
        case .libraryTracking:
            LibraryProfileHubRow(
                title: destination.title, subtitle: "Defaults, filters, categories, progress",
                systemImage: "slider.horizontal.3", tint: destination.tint)
        case .appearance:
            LibraryProfileHubRow(
                title: destination.title, subtitle: "Tap behavior, detail display, sharing",
                systemImage: "rectangle.3.group.fill", tint: destination.tint)
        case .reminders:
            LibraryProfileHubRow(
                title: destination.title, systemImage: "bell.badge.fill", tint: destination.tint,
                value: reminderSummary,
                warning: remindersLoaded && (reminders.snapshot.warning != nil || reminders.lastRefreshFailed))
        case .metadataImages:
            LibraryProfileHubRow(
                title: destination.title, subtitle: "TMDb, cache, refresh", systemImage: "photo.stack",
                tint: destination.tint)
        case .syncData:
            LibraryProfileHubRow(
                title: destination.title, systemImage: "icloud", tint: destination.tint,
                value: syncStatus.settingsHubStatus.title,
                warning: syncStatus.isEnabled
                    && (syncStatus.settingsIssueCount > 0 || syncStatus.isFailureDisplay
                        || syncStatus.bootstrapState == .needsConflictChoice)
            )
        }
    }

    private var reminderSummary: LocalizedStringResource {
        guard remindersLoaded else { return "…" }
        if reminders.snapshot.authorizationStatus == .denied { return "Notifications Off" }
        if reminders.snapshot.warning != nil || reminders.lastRefreshFailed { return "Needs Attention" }
        return "\(reminders.snapshot.subscriptions.count) anime"
    }
}

/// What's New, Support, and About; shared by the hub and the regular-width workspace.
struct LibraryProfileAppInfoCard: View {
    enum Style {
        /// A titled card, matching the hub's Settings card.
        case card
        /// Rows in an inset panel; the workspace titles it like its other groups.
        case panel
    }

    @Environment(\.colorScheme) private var colorScheme
    var style: Style = .card
    let whatsNewVersion: String?
    let onShowWhatsNew: () -> Void
    let onShowSupport: () -> Void
    let onShowAbout: () -> Void

    var body: some View {
        switch style {
        case .card:
            PopupSectionCard("App Info", systemImage: "app.badge", spacing: 8, panelTint: cardTint) {
                rows
            }
        case .panel:
            rows
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileSettingsPalette.appInfo)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if let whatsNewVersion {
                Button(action: onShowWhatsNew) {
                    LibraryProfileHubRow(
                        title: "What's New", systemImage: "sparkles.rectangle.stack",
                        tint: LibraryProfileSettingsPalette.appInfo,
                        value: "\(whatsNewVersion)")
                }
                LibraryProfileActionDivider(leadingInset: 44)
            }
            Button(action: onShowSupport) {
                LibraryProfileHubRow(
                    title: "Support AniShelf", systemImage: "heart.circle",
                    tint: LibraryProfileSettingsPalette.appInfo)
            }
            LibraryProfileActionDivider(leadingInset: 44)
            Button(action: onShowAbout) {
                LibraryProfileHubRow(
                    title: "About AniShelf", systemImage: "info.circle",
                    tint: LibraryProfileSettingsPalette.appInfo)
            }
        }
        .buttonStyle(.plain)
    }

    private var cardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }
}

fileprivate struct LibraryProfileHubRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    let systemImage: String
    let tint: Color
    var value: LocalizedStringResource?
    var warning = false

    var body: some View {
        HStack(spacing: 10) {
            LibraryProfileSettingIcon(systemImage: systemImage, tint: tint)
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 12) {
                        titleBlock.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        status.fixedSize(horizontal: true, vertical: false)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    titleBlock
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var status: some View {
        if let value {
            HStack(spacing: 4) {
                if warning { Image(systemName: "exclamationmark.triangle.fill") }
                Text(value)
            }
            .font(.caption)
            .foregroundStyle(warning ? .orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
