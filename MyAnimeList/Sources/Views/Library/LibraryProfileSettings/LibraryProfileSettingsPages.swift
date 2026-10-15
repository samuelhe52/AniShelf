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
                .accessibilityLabel(Text(LocalizedStringResource("Close")))
            }
            #endif
        }
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
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(title: title, systemImage: systemImage, tint: tint)
            content()
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: tint)
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
            LibraryProfileSettingsToggleRow(
                title: "Cache Large Gallery Posters",
                subtitle: "Store large Gallery posters longer. Off by default and may use more disk space.",
                isOn: $longTermGalleryPosterCachingEnabled
            )
        }
        // Actions keep the former Maintenance card's icon rows and dividers.
        VStack(spacing: 0) {
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
        }
        .padding(.vertical, 4)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: tint)
    }
}
