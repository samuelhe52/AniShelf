//
//  LibraryProfileInterfaceSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

struct LibraryProfileInterfaceSettingsSection: View {
    @AppStorage(.showProductionCompanyInsteadOfRuntime)
    private var showProductionCompanyInsteadOfRuntime = false

    @Binding var openDetailWithSingleTap: Bool
    @Binding var entryDetailCharactersExpandedByDefault: Bool
    @Binding var entryDetailStaffExpandedByDefault: Bool
    @Binding var scoringEnabled: Bool
    @Binding var episodeProgressTrackingEnabled: Bool
    @Binding var posterProgressBarOverlayEnabled: Bool
    @Binding var useSoftNavigationBarEdges: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Interface",
                systemImage: "rectangle.3.group.fill",
                tint: .teal
            )

            LibraryProfileSettingsToggleRow(
                title: "Open Detail with Single Tap",
                subtitle: "By default, double tap opens detail. Turn this on to use single tap instead.",
                isOn: $openDetailWithSingleTap,
                tint: .teal
            )

            LibraryProfileSettingsToggleRow(
                title: "Expand Characters by Default",
                subtitle: "Open the Characters section automatically in entry detail view.",
                isOn: $entryDetailCharactersExpandedByDefault,
                tint: .teal
            )

            LibraryProfileSettingsToggleRow(
                title: "Expand Staff by Default",
                subtitle: "Open the Staff section automatically in entry detail view.",
                isOn: $entryDetailStaffExpandedByDefault,
                tint: .teal
            )

            LibraryProfileSettingsToggleRow(
                title: "Show production company instead of runtime",
                subtitle: "Applies to series and seasons when both are available.",
                isOn: $showProductionCompanyInsteadOfRuntime,
                tint: .teal
            )

            LibraryProfileSettingsToggleRow(
                title: "Enable Scoring",
                subtitle: "Turning this off does not delete previously saved scores.",
                isOn: $scoringEnabled,
                tint: .teal
            )

            LibraryProfileSettingsToggleRow(
                title: "Track Episode Progress",
                subtitle: "Turning this off hides episode progress without deleting saved progress.",
                isOn: $episodeProgressTrackingEnabled,
                tint: .teal
            )

            if episodeProgressTrackingEnabled {
                LibraryProfileSettingsToggleRow(
                    title: "Show Poster Progress Bar",
                    subtitle: "Show episode progress as a poster overlay in the library.",
                    isOn: $posterProgressBarOverlayEnabled,
                    tint: .teal
                )
            }

            if #available(iOS 27, *) {
                LibraryProfileSettingsToggleRow(
                    title: "Use Soft Navigation Bar Edges",
                    subtitle:
                        "Available on iOS 27 or later. Turn off to use the system appearance.",
                    isOn: $useSoftNavigationBarEdges,
                    tint: .teal
                )
            }
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .teal)
    }
}

struct LibraryProfileTMDbConnectionSection: View {
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
