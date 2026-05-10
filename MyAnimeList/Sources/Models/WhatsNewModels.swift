//
//  WhatsNewModels.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/9.
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
        )
    ]

    static func currentEntry(for version: String) -> WhatsNewEntry? {
        entriesByVersion[version]
    }
}
