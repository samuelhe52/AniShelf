//
//  WhatsNewModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/9.
//

import Foundation
import SwiftUI

struct WhatsNewEntry: Identifiable {
    struct Action: Identifiable {
        enum Kind: Equatable {
            case refreshMetadata
            case openURL(URL)
        }

        let id: String
        let title: LocalizedStringResource
        let systemImage: String
        let kind: Kind
    }

    let id: String
    let version: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let highlights: [LocalizedStringResource]
    let primaryAction: Action?
    let secondaryActions: [Action]

    init(
        version: String,
        title: LocalizedStringResource? = nil,
        summary: LocalizedStringResource,
        highlights: [LocalizedStringResource],
        primaryAction: Action? = nil,
        secondaryActions: [Action] = []
    ) {
        self.id = version
        self.version = version
        self.title = title ?? "Version \(version)"
        self.summary = summary
        self.highlights = highlights
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }
}

enum WhatsNewRegistry {
    private static let projectURL = URL(string: "https://github.com/samuelhe52/AniShelf")!

    private static let entriesByVersion: [String: WhatsNewEntry] = [
        "1.54": .init(
            version: "1.54",
            title: "Built-in release notes",
            summary: "AniShelf can now show selected update notes after launch and reopen them later from Settings.",
            highlights: [
                "Important release notes can now appear once after you update the app.",
                "The current release note stays available from Settings whenever this version includes one.",
                "This page can also trigger a full metadata refresh if you want to update existing entries right away."
            ],
            primaryAction: .init(
                id: "refresh-metadata",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            ),
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.60": .init(
            version: "1.60",
            summary:
                "This version includes multiple bug fixes and improvements. It is recommended that existing users perform a metadata refresh by tapping the action button below, as this version includes important optimizations for metadata retrieval.",
            highlights: [
                "Optimized the Details page UI: added Staff information, added an overscroll zoom effect for posters.",
                "Fixed a crash issue when converting to an animation series.",
                "Added a setting option to open the details page with a single click."
            ],
            primaryAction: .init(
                id: "refresh-metadata",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            ),
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.70": .init(
            version: "1.70",
            summary:
                "This version includes multiple bug fixes and improvements. It is recommended that existing users perform a metadata refresh by tapping the action button below, as this version includes important optimizations for metadata retrieval.",
            highlights: [
                "Added a rating feature: you can now rate anime in your library from 1 to 5.",
                "Added TV anime / movie filtering.",
                "Added multi-format export: you can now export your library in formats such as txt, csv, and xlsx.",
                "Added grouped display: entries can now be grouped and sorted by watch status, rating, or favorite status.",
                "Added bulk-add support: you can trigger it from the top-right button on the search screen.",
                "Fixed an issue with Staff display on the details page.",
                "Fixed an issue where some entries could not be updated after changing metadata language and refreshing metadata."
            ],
            primaryAction: .init(
                id: "refresh-metadata",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            ),
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.72": .init(
            version: "1.72",
            summary:
                "This version includes multiple bug fixes and improvements. It is recommended that existing users perform a metadata refresh by tapping the action button below, as this version includes important optimizations for metadata retrieval.",
            highlights: [
                "Added an option in settings to enable the rating feature, allowing the rating module to be shown or hidden on the details page.",
                "Allowed showing or hiding start/end dates for individual entries in entry detail sheet.",
                "Fixed bugs related to default poster selection."
            ],
            primaryAction: .init(
                id: "refresh-metadata",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            ),
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.81": .init(
            version: "1.81",
            summary:
                "This version includes multiple bug fixes and improvements.",
            highlights: [
                "Ratings are now shown directly in List and Gallery views.",
                "Optimized backup file size.",
                "Added sorting by name (A–Z)."
            ],
            primaryAction: nil,
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.90": .init(
            version: "1.90",
            summary:
                "This version includes multiple UX optimizations and feature improvements. It is recommended that existing users perform an info refresh by tapping the action button below so existing entries can pick up the latest metadata improvements.",
            highlights: [
                "Added optional episode-level progress tracking. To use this feature, enable it in settings.",
                "Improved watch status switching and date selection UX.",
                "Library overview now supports tap-to-toggle watched time, planned time, and total time.",
                "TMDb Proxy is now disabled by default, with improved search error UX."
            ],
            primaryAction: .init(
                id: "refresh-metadata",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            ),
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.91": .init(
            version: "1.91",
            summary:
                "This version includes feature updates and visual improvements.",
            highlights: [
                "On the details page, long-press an episode to view that episode's staff.",
                "On the details page, the Episodes section now shows watch progress.",
                "Added a tipping option in Settings (tips are available only in the App Store version). Thanks for your support!",
                "Updated the icon shown when loading fails."
            ],
            primaryAction: nil,
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.92": .init(
            version: "1.92",
            summary:
                "This version adds iCloud sync and includes UI improvements.",
            highlights: [
                "Added iCloud sync for your library and user settings. Turn it on manually in Settings.",
                "Improved the rating UI.",
                "Fixed an occasional scrolling jitter issue on the poster selection page."
            ],
            primaryAction: nil,
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.93": .init(
            version: "1.93",
            summary:
                "This version includes bug fixes and search improvements.",
            highlights: [
                "Batch search now supports adding by TMDb ID.",
                "Fixed a problem where info refresh could hang the app.",
                "Fixed an issue where adding certain anime could fail and occasionally crash the app.",
                "Fixed an issue where deleted entries could sometimes reappear after sync."
            ],
            primaryAction: nil,
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.94": .init(
            version: "1.94",
            summary:
                "This release fixes data correctness issues. Existing users should perform an info refresh by tapping the action button below so their library metadata can be corrected.",
            highlights: [
                "Fixed an issue where iCloud sync could fail when the library became very large.",
                "Reduced disk usage. Existing users can optionally clear cache and reload metadata from Settings to reclaim more storage.",
                "Added a Settings option to cache large Gallery posters (off by default)."
            ],
            primaryAction: .init(
                id: "refresh-metadata",
                title: "Refresh Metadata",
                systemImage: "arrow.clockwise",
                kind: .refreshMetadata
            ),
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.95": .init(
            version: "1.95",
            summary:
                "This release adds thoughtful review prompts and improves the reliability of TMDb artwork and setup.",
            highlights: [
                "AniShelf can now ask for an App Store review after sustained, meaningful use, without interrupting what you are doing.",
                "TMDb logos now support SVG artwork for sharper images.",
                "Improved TMDb API key handling at launch to avoid unnecessary setup prompts."
            ],
            primaryAction: nil,
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        ),
        "1.96": .init(
            version: "1.96",
            summary: "This release improves AniShelf on iPad and larger displays.",
            highlights: [
                "AniShelf now adapts to resizable iPad windows for a more natural large-screen experience.",
                "Added a Dark Mode app icon."
            ],
            primaryAction: nil,
            secondaryActions: [
                .init(
                    id: "project-github",
                    title: "AniShelf on GitHub",
                    systemImage: "arrow.up.right.square",
                    kind: .openURL(projectURL)
                )
            ]
        )
    ]

    static func currentEntry(for version: String) -> WhatsNewEntry? {
        entriesByVersion[version]
    }
}
