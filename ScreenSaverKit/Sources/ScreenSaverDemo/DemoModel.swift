//
//  DemoModel.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import Foundation
import Observation
import ScreenSaverKit

enum DemoLayout: Hashable, Identifiable {
    case shipped(ScreenSaverManifest.Layout)
    case draft(ScreenSaverDraftLayout)

    static let shippedCases = ScreenSaverManifest.Layout.allCases.map(DemoLayout.shipped)
    static let draftCases = ScreenSaverDraftLayout.allCases.map(DemoLayout.draft)

    var id: String {
        switch self {
        case .shipped(let layout): "shipped." + layout.rawValue
        case .draft(let layout): "draft." + layout.rawValue
        }
    }

    var title: String {
        switch self {
        case .shipped(.coverWall): "Cover Wall"
        case .shipped(.posterFocus): "Poster Focus"
        case .shipped(.backdrop): "Backdrop"
        case .draft(.deckFan): "Deck · Fan"
        case .draft(.deckPile): "Deck · Pile"
        case .draft(.flipWall): "Flip Wall"
        case .draft(.coverFusion): "Cover Fusion"
        case .draft(.seasonTimeline): "Season Timeline"
        case .draft(.depthDrift): "Depth Drift"
        case .draft(.editorialCover): "Editorial Cover"
        }
    }

    var usesInterval: Bool {
        switch self {
        case .shipped(.coverWall), .draft(.flipWall), .draft(.depthDrift), .draft(.seasonTimeline): false
        default: true
        }
    }

    var usesRows: Bool { self == .shipped(.coverWall) || self == .draft(.flipWall) }

    /// Layouts drawn over the flowing mesh wash.
    var usesWash: Bool {
        switch self {
        case .shipped(.coverWall), .shipped(.backdrop), .draft(.flipWall): false
        default: true
        }
    }

    var usesDetails: Bool {
        switch self {
        case .shipped(.coverWall), .draft(.flipWall), .draft(.depthDrift): false
        default: true
        }
    }

    /// The shipped layout whose details a draft borrows.
    var settingsLayout: ScreenSaverManifest.Layout {
        if case .shipped(let layout) = self { return layout }
        return .posterFocus
    }
}

struct ScreenPreset: Hashable, Identifiable {
    let name: String
    /// Nil fills the view at its real size.
    let size: CGSize?

    var id: String { name }

    static let all: [ScreenPreset] = [
        .init(name: "16:10 · 1512 × 982", size: CGSize(width: 1512, height: 982)),
        .init(name: "16:9 · 1920 × 1080", size: CGSize(width: 1920, height: 1080)),
        .init(name: "4:3 · 1600 × 1200", size: CGSize(width: 1600, height: 1200)),
        .init(name: "21:9 · 3440 × 1440", size: CGSize(width: 3440, height: 1440)),
        .init(name: "32:9 · 5120 × 1440", size: CGSize(width: 5120, height: 1440)),
        .init(name: "Portrait · 1080 × 1920", size: CGSize(width: 1080, height: 1920)),
        .init(name: "Fill the view", size: nil)
    ]
}

/// Everything that restarts playback when it changes.
struct DemoConfiguration: Equatable {
    var directory: URL
    var draft: ScreenSaverDraft
}

@MainActor
@Observable
final class DemoModel {
    static let entryLimits = [1, 2, 3, 4, 6, 8, 12, 20]

    var directory: URL {
        didSet { readEntryCount() }
    }
    var layout = DemoLayout.draft(.deckFan)
    var preset = ScreenPreset.all[0]
    /// Nil plays every entry in the snapshot.
    var entryLimit: Int?
    var interval: Double = 6
    var rows = ScreenSaverManifest.Settings.defaultCoverWallRows
    var flipDelay: Double = 6
    var driftRate: Double = 4
    var deckDepth = 5
    var pileDepth = 7
    var timelineHold: Double = 7
    var washFlows = true
    /// Speeds playback up; only `--capture` sets it.
    var speed: Double = 1
    var details: Set<ScreenSaverManifest.Detail> = [.season, .year, .genres, .watchStatus, .userScore, .overview]
    var seed = UInt64.random(in: .min ... .max)
    private(set) var entryCount: Int?

    init(directory: URL? = nil) {
        self.directory =
            directory
            ?? ScreenSaverSnapshotReader.snapshotDirectory(in: FileManager.default.homeDirectoryForCurrentUser)
        readEntryCount()
    }

    var configuration: DemoConfiguration {
        var draft = ScreenSaverDraft(
            settings: .init(
                layout: layout.settingsLayout, details: Array(details), interval: interval, coverWallRows: rows,
                washFlows: washFlows),
            entryLimit: entryLimit, seed: seed)
        if case .draft(let layout) = layout { draft.layout = layout }
        draft.timeScale = speed
        draft.flipDelay = flipDelay
        draft.driftRate = driftRate
        draft.deckDepth = deckDepth
        draft.pileDepth = pileDepth
        draft.timelineHold = timelineHold
        return DemoConfiguration(directory: directory, draft: draft)
    }

    func reshuffle() {
        seed = UInt64.random(in: .min ... .max)
    }

    private func readEntryCount() {
        switch ScreenSaverSnapshotReader(directory: directory).read() {
        case .ready(let manifest): entryCount = manifest.entries.count
        case .empty, .requiresUpdate: entryCount = nil
        }
    }
}
