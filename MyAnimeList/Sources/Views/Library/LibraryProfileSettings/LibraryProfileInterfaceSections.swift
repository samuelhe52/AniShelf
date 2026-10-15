//
//  LibraryProfileInterfaceSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

struct LibraryProfileInterfaceSettingsSection: View {
    @AppStorage(.libraryOpenDetailWithSingleTap) private var openDetailWithSingleTap = false
    @AppStorage(.entryDetailCharactersExpandedByDefault)
    private var entryDetailCharactersExpandedByDefault = true
    @AppStorage(.entryDetailStaffExpandedByDefault)
    private var entryDetailStaffExpandedByDefault = false
    @AppStorage(.useSoftNavigationBarEdges) private var useSoftNavigationBarEdges = true
    @AppStorage(.showProductionCompanyInsteadOfRuntime)
    private var showProductionCompanyInsteadOfRuntime = false

    var body: some View {
        VStack(spacing: 16) {
            // A click always opens the inspector on the Mac, and its toolbar has no soft edge option.
            #if !os(macOS)
            LibraryProfileSettingsSection(
                "Library", systemImage: "hand.tap", tint: LibraryProfileSettingsDestination.appearance.tint
            ) {
                LibraryProfileSettingsToggleRow(
                    title: "Open Detail with Single Tap",
                    subtitle: "By default, double tap opens detail. Turn this on to use single tap instead.",
                    isOn: $openDetailWithSingleTap
                )

                if #available(iOS 27, *) {
                    LibraryProfileSettingsToggleRow(
                        title: "Use Soft Navigation Bar Edges",
                        subtitle:
                            "Available on iOS 27 or later. Turn off to use the system appearance.",
                        isOn: $useSoftNavigationBarEdges
                    )
                }
            }
            #endif
            LibraryProfileSettingsSection(
                "Entry Details", systemImage: "rectangle.3.group.fill",
                tint: LibraryProfileSettingsDestination.appearance.tint
            ) {
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
                    title: "Show production company instead of runtime",
                    subtitle: "Applies to series and seasons when both are available.",
                    isOn: $showProductionCompanyInsteadOfRuntime
                )
            }
            LibraryProfileSharingSettingsSection()
        }
    }
}

struct LibraryProfileTMDbConnectionSection: View {
    var onChangeAPIKey: () -> Void = {}
    @AppStorage(.useTMDbRelayServer) private var useTMDbRelayServer = false
    @State private var showRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "TMDb Connection",
                subtitle: "Turn this on if direct TMDb access is unstable on your network.",
                systemImage: "network",
                tint: LibraryProfileSettingsDestination.metadataImages.tint
            )

            LibraryProfileSettingsToggleRow(
                title: "Use TMDb Proxy",
                subtitle: "Turn this off if you use a VPN or another proxy.",
                isOn: $useTMDbRelayServer
            )
            LibraryProfileActionRow(
                title: "Change API Key",
                subtitle: "Update the TMDb key used for metadata.",
                systemImage: "person.badge.key",
                tint: LibraryProfileSettingsDestination.metadataImages.tint,
                horizontalPadding: 0,
                showsIcon: false,
                action: onChangeAPIKey
            )
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileSettingsDestination.metadataImages.tint)
        .alert("TMDb Proxy Updated", isPresented: $showRestartAlert) {
            Button("OK") {}
        } message: {
            Text("You might need to restart the app for this change to take effect.")
        }
        .onChange(of: useTMDbRelayServer, handleTMDbRelayServerChange)
    }

    private func handleTMDbRelayServerChange(old: Bool, new: Bool) {
        guard old != new else { return }
        NotificationCenter.default.post(
            name: .tmdbAPIConfigurationDidChange,
            object: nil
        )
        showRestartAlert = true
    }
}

struct LibraryProfileTrackingSettingsSection: View {
    @Environment(LibraryStore.self) private var store
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true
    @AppStorage(.episodeProgressTrackingEnabled) private var episodeProgressTrackingEnabled = false
    @AppStorage(.libraryPosterProgressBarOverlayEnabled)
    private var posterProgressBarOverlayEnabled = true

    var body: some View {
        LibraryProfileSettingsSection(
            "Tracking", systemImage: "checkmark.circle", tint: LibraryProfileSettingsDestination.libraryTracking.tint
        ) {
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
        }
        .onChange(of: scoringEnabled, handleScoringEnabledChange)
    }

    private func handleScoringEnabledChange(old: Bool, new: Bool) {
        guard old != new, !new, store.groupStrategy == .score else { return }
        store.groupStrategy = .none
    }
}

fileprivate struct LibraryProfileSharingSettingsSection: View {
    @AppStorage(.rememberShareSheetSettings) private var rememberShareSheetSettings = false

    var body: some View {
        LibraryProfileSettingsSection(
            "Sharing", systemImage: "square.and.arrow.up", tint: LibraryProfileSettingsDestination.appearance.tint
        ) {
            LibraryProfileSettingsToggleRow(
                title: "Remember Share Settings",
                subtitle:
                    "Remember language, corner style, image format, and export size preferences in the share sheet.",
                isOn: $rememberShareSheetSettings
            )
        }
        .onChange(of: rememberShareSheetSettings, handleRememberShareSheetSettingsChange)
    }

    private func handleRememberShareSheetSettingsChange(old: Bool, new: Bool) {
        guard old != new, !new else { return }
        AnimeSharingPreferences().resetRememberedSettings()
    }
}
