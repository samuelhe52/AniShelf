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
        title: LocalizedStringResource,
        summary: LocalizedStringResource,
        highlights: [LocalizedStringResource],
        primaryAction: Action? = nil,
        secondaryActions: [Action] = []
    ) {
        self.id = version
        self.version = version
        self.title = title
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
        )
    ]

    static func currentEntry(for version: String) -> WhatsNewEntry? {
        entriesByVersion[version]
    }
}
