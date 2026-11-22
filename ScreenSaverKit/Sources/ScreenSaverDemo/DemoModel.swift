//
//  DemoModel.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import Foundation
import Observation
import ScreenSaverKit

extension ScreenSaverManifest.Layout {
    var title: String {
        switch self {
        case .coverWall: "Cover Wall"
        case .posterFocus: "Poster Focus"
        case .backdrop: "Backdrop"
        case .deckFan: "Deck · Fan"
        case .deckPile: "Deck · Pile"
        case .flipWall: "Flip Wall"
        case .coverFusion: "Cover Fusion"
        case .timeline: "Timeline"
        case .depthDrift: "Depth Drift"
        case .editorialCover: "Editorial Cover"
        }
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
    var settings: ScreenSaverManifest.Settings
    var playbackOptions: ScreenSaverPlaybackOptions
}

@MainActor
@Observable
final class DemoModel {
    typealias Settings = ScreenSaverManifest.Settings

    static let entryLimits = [1, 2, 3, 4, 6, 8, 12, 20]

    var directory: URL {
        didSet { readEntryCount() }
    }
    var layout = ScreenSaverManifest.Layout.deckFan
    var preset = ScreenPreset.all[0]
    /// Nil plays every entry in the snapshot.
    var entryLimit: Int?
    var interval = Settings.defaultInterval
    var rows = Settings.defaultCoverWallRows
    var flipDelay = Settings.defaultFlipDelay
    var driftRate = Settings.defaultDriftRate
    var deckDepth = Settings.defaultDeckDepth
    var pileDepth = Settings.defaultPileDepth
    var timelineHold = Settings.defaultTimelineHold
    var timelineDateSource: ScreenSaverManifest.TimelineDateSource = .airDate
    var timelineDatePrecision: ScreenSaverManifest.TimelineDatePrecision = .fullDate
    var washFlows = true
    var washSpeed: Double = 1
    var posterOverviewLines = Settings.defaultPosterOverviewLines
    var backdropSubjectAwareText = Settings.defaultBackdropSubjectAwareText
    /// Speeds playback up; only `--capture` sets it.
    var speed: Double = 1
    private var details: Set<ScreenSaverManifest.Detail> = [.year, .genres, .watchStatus, .userScore, .overview]
    private var taglineSelections: [ScreenSaverManifest.Layout: Bool] = [:]
    var seed = UInt64.random(in: .min ... .max)
    private(set) var entryCount: Int?
    private(set) var timelineDateCounts: [ScreenSaverManifest.TimelineDateSource: Int] = [:]

    init(directory: URL? = nil) {
        self.directory =
            directory
            ?? ScreenSaverSnapshotReader.snapshotDirectory(in: FileManager.default.homeDirectoryForCurrentUser)
        readEntryCount()
    }

    var optionsLayout: ScreenSaverManifest.Layout {
        guard let entryCount else { return layout }
        return layout.layout(forPosterCount: min(entryCount, entryLimit ?? entryCount))
    }

    func isDetailEnabled(_ detail: ScreenSaverManifest.Detail) -> Bool {
        guard detail == .tagline else { return details.contains(detail) }
        let selectionLayout = layout.detailSelectionLayout
        return taglineSelections[selectionLayout]
            ?? ScreenSaverManifest.Detail.defaults(for: selectionLayout).contains(.tagline)
    }

    func setDetail(_ detail: ScreenSaverManifest.Detail, enabled: Bool) {
        if detail == .tagline {
            taglineSelections[layout.detailSelectionLayout] = enabled
        } else if enabled {
            details.insert(detail)
        } else {
            details.remove(detail)
        }
    }

    var configuration: DemoConfiguration {
        let available = ScreenSaverManifest.Detail.available(for: layout.detailSelectionLayout)
        return DemoConfiguration(
            directory: directory,
            settings: .init(
                layout: layout, details: available.filter(isDetailEnabled), interval: interval, coverWallRows: rows,
                washFlows: washFlows, washSpeed: washSpeed, flipDelay: flipDelay, driftRate: driftRate,
                deckDepth: deckDepth, pileDepth: pileDepth, timelineHold: timelineHold,
                timelineDateSource: timelineDateSource, timelineDatePrecision: timelineDatePrecision,
                posterOverviewLines: posterOverviewLines, backdropSubjectAwareText: backdropSubjectAwareText),
            playbackOptions: .init(entryLimit: entryLimit, seed: seed, timeScale: speed))
    }

    /// Also picks up a snapshot AniShelf wrote since the folder was chosen.
    func reshuffle() {
        seed = UInt64.random(in: .min ... .max)
        readEntryCount()
    }

    private func readEntryCount() {
        switch ScreenSaverSnapshotReader(directory: directory).read() {
        case .ready(let manifest):
            entryCount = manifest.entries.count
            timelineDateCounts = Dictionary(
                uniqueKeysWithValues: ScreenSaverManifest.TimelineDateSource.allCases.map { source in
                    (source, manifest.entries.count { source.date(for: $0) != nil })
                })
        case .empty, .requiresUpdate:
            entryCount = nil
            timelineDateCounts = [:]
        }
    }
}
