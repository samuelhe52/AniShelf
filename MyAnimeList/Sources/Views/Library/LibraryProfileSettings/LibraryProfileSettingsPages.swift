//
//  LibraryProfileSettingsPages.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/13.
//

import DataProvider
import SwiftUI

/// Shared destination chrome; the enclosing profile owns the navigation stack.
struct LibraryProfileSettingsPage<Content: View>: View {
    let destination: LibraryProfileSettingsDestination
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        pageBody
            .environment(\.libraryProfilePageTint, destination.tint)
            .navigationTitle(destination.title)
            .inlineNavigationTitle()
            .hiddenNavigationBarBackground()
            .toolbar {
                // The Settings window closes like any Mac window.
                #if !os(macOS)
                    ToolbarItem(placement: .platformTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Close"))
                    }
                #endif
            }
    }
}

extension LibraryProfileSettingsPage {
    @ViewBuilder
    fileprivate var pageBody: some View {
        #if os(macOS)
            // A grouped form, as in System Settings: each settings section becomes a form
            // section and each row a standard form row.
            Form(content: content)
                .formStyle(.grouped)
        #else
            ZStack {
                LibraryProfileBackdrop()
                ScrollView {
                    VStack(spacing: 16, content: content)
                        .frame(maxWidth: 720)
                        .padding(18)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
                .preferredNavigationBarScrollEdgeEffect()
            }
        #endif
    }
}

struct LibraryProfileSettingsSection<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringResource, systemImage: String, tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content
    }

    var body: some View {
        LibraryProfileSettingsGroup(title, systemImage: systemImage, tint: tint, content: content)
    }
}

/// A settings section: a tinted card with an icon header on iOS, a grouped form section on
/// the Mac.
///
/// A subtitle becomes the Mac section's footer.
struct LibraryProfileSettingsGroup<Content: View>: View {
    let title: LocalizedStringResource?
    var subtitle: LocalizedStringResource? = nil
    let systemImage: String
    let tint: Color
    var spacing: CGFloat = 10
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringResource?, subtitle: LocalizedStringResource? = nil, systemImage: String,
        tint: Color, spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if os(macOS)
            Section {
                content()
            } header: {
                if let title { Text(title) }
            } footer: {
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        #else
            VStack(alignment: .leading, spacing: spacing) {
                if let title {
                    LibraryProfileSettingHeader(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
                }
                content()
            }
            .padding(14)
            .libraryProfileInsetPanel(cornerRadius: 22, tint: tint)
        #endif
    }
}

struct LibraryProfileBroadcastSettingsSection: View {
    @AppStorage(.broadcastScheduleEnabled) private var broadcastScheduleEnabled = true

    var body: some View {
        LibraryProfileSettingsSection(
            "Broadcast", systemImage: "antenna.radiowaves.left.and.right",
            tint: LibraryProfileSettingsDestination.reminders.tint
        ) {
            LibraryProfileSettingsToggleRow(
                title: "Broadcast Airtimes",
                subtitle: "Look up TV broadcast times when you open an eligible anime or season.",
                isOn: $broadcastScheduleEnabled
            )
        }
    }
}

struct LibraryProfileMetadataImagesPage: View {
    @Binding var autoPrefetchImagesOnAddAndRestore: Bool
    @Binding var longTermGalleryPosterCachingEnabled: Bool
    let onChangeAPIKey: () -> Void
    let onCheckMetadataCacheSize: () -> Void
    let onRefreshInfos: () -> Void
    /// A refresh is already running, from this or another window.
    var isRefreshingInfos = false
    let onPrefetchImages: () -> Void

    private var tint: Color { LibraryProfileSettingsDestination.metadataImages.tint }

    var body: some View {
        LibraryProfileTMDbConnectionSection(onChangeAPIKey: onChangeAPIKey)
        LibraryProfileSettingsSection("Images", systemImage: "photo.stack", tint: tint) {
            LibraryProfileSettingsToggleRow(
                title: "Auto Prefetch Images",
                subtitle: "Prefetch images when adding titles or restoring a backup.",
                isOn: $autoPrefetchImagesOnAddAndRestore
            )
            #if !os(macOS)
                // The Mac has no Gallery.
                LibraryProfileSettingsToggleRow(
                    title: "Cache Large Gallery Posters",
                    subtitle: "Store large Gallery posters longer. Off by default and may use more disk space.",
                    isOn: $longTermGalleryPosterCachingEnabled
                )
            #endif
        }
        // Actions keep the former Maintenance card's icon rows and dividers.
        #if os(macOS)
            Section { maintenanceRows }
        #else
            VStack(spacing: 0) { maintenanceRows }
                .padding(.vertical, 4)
                .libraryProfileInsetPanel(cornerRadius: 22, tint: tint)
        #endif
    }

    @ViewBuilder
    private var maintenanceRows: some View {
        LibraryProfileActionRow(
            title: "Prefetch Images",
            subtitle: "Cache posters and artwork without refreshing metadata.",
            systemImage: "photo.stack", tint: tint, action: onPrefetchImages
        )
        LibraryProfileActionDivider()
        LibraryProfileActionRow(
            title: "Check Metadata Cache Size",
            subtitle: "Review image and metadata cache usage.",
            systemImage: "archivebox", tint: tint, action: onCheckMetadataCacheSize
        )
        LibraryProfileActionDivider()
        LibraryProfileActionRow(
            title: "Refresh Infos",
            subtitle: "Fetch latest TMDb metadata for every entry.",
            systemImage: "arrow.clockwise", tint: tint, action: onRefreshInfos
        )
        .disabled(isRefreshingInfos)
    }
}
