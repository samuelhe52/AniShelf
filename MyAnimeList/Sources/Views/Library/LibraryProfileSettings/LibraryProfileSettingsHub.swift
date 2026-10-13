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
    let columns: LibraryProfileSettingsHubColumns
    @Binding var followsSystemLanguage: Bool
    @Binding var preferredLanguage: Language
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
                    LibraryProfileLanguageSettingsRow(
                        followsSystemLanguage: $followsSystemLanguage, preferredLanguage: $preferredLanguage
                    )
                    LibraryProfileActionDivider(leadingInset: 44)
                    if columns == .double {
                        // Column-major halves keep each column's reading order intact.
                        HStack(alignment: .top, spacing: 16) {
                            destinationColumn(Array(Self.destinations.prefix(3)))
                            destinationColumn(Array(Self.destinations.dropFirst(3)))
                        }
                    } else {
                        destinationColumn(Self.destinations)
                    }
                }
            }

            PopupSectionCard("App Info", systemImage: "app.badge", spacing: 8, panelTint: cardTint) {
                VStack(spacing: 0) {
                    if let whatsNewVersion {
                        Button(action: onShowWhatsNew) {
                            LibraryProfileHubRow(
                                title: "What's New", systemImage: "sparkles.rectangle.stack",
                                tint: LibraryProfileSettingsPalette.step(6),
                                value: LocalizedStringResource("\(whatsNewVersion)"))
                        }
                        LibraryProfileActionDivider(leadingInset: 44)
                    }
                    Button(action: onShowSupport) {
                        LibraryProfileHubRow(
                            title: "Support AniShelf", systemImage: "heart.circle",
                            tint: LibraryProfileSettingsPalette.step(7))
                    }
                    LibraryProfileActionDivider(leadingInset: 44)
                    Button(action: onShowAbout) {
                        LibraryProfileHubRow(
                            title: "About AniShelf", systemImage: "info.circle",
                            tint: LibraryProfileSettingsPalette.step(8))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }

    private static let destinations = LibraryProfileSettingsDestination.allCases

    private func destinationColumn(_ destinations: [LibraryProfileSettingsDestination]) -> some View {
        VStack(spacing: 0) {
            ForEach(destinations, id: \.self) { destination in
                if destination != destinations.first {
                    LibraryProfileActionDivider(leadingInset: 44)
                }
                NavigationLink(value: destination) {
                    row(destination)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func row(_ destination: LibraryProfileSettingsDestination) -> some View {
        switch destination {
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
