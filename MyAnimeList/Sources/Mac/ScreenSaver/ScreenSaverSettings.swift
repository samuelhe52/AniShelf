//
//  ScreenSaverSettings.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import DataProvider
    import Foundation
    import ScreenSaverKit

    struct ScreenSaverSettings: Equatable {
        typealias Layout = ScreenSaverManifest.Layout
        typealias Detail = ScreenSaverManifest.Detail
        typealias ManifestSettings = ScreenSaverManifest.Settings

        enum Scope: Hashable {
            case favorites
            case watched
            case all
            /// A custom library category. A deleted category matches nothing; its memberships stay
            /// inert because category IDs are never reused.
            case category(LibraryCategory.ID)

            static let builtIn: [Scope] = [.favorites, .watched, .all]
            private static let categoryPrefix = "category:"

            init?(rawValue: String) {
                switch rawValue {
                case "favorites": self = .favorites
                case "watched": self = .watched
                case "all": self = .all
                default:
                    guard rawValue.hasPrefix(Self.categoryPrefix) else { return nil }
                    let id = String(rawValue.dropFirst(Self.categoryPrefix.count))
                    guard !id.isEmpty else { return nil }
                    self = .category(id)
                }
            }

            var rawValue: String {
                switch self {
                case .favorites: "favorites"
                case .watched: "watched"
                case .all: "all"
                case .category(let id): Self.categoryPrefix + id
                }
            }

            func includes(_ entry: AnimeEntry) -> Bool {
                switch self {
                case .favorites: entry.favorite
                case .watched: entry.watchStatus == .watched
                case .all: true
                case .category(let id): entry.categoryIDs.contains(id)
                }
            }
        }

        static let enabledKey = "screenSaverEnabled"
        static let scopeKey = "screenSaverScope"
        static let layoutKey = "screenSaverLayout"
        static let intervalKey = "screenSaverInterval"
        static let coverWallRowsKey = "screenSaverCoverWallRows"
        static let washFlowsKey = "screenSaverWashFlows"
        static let washSpeedKey = "screenSaverWashSpeed"
        static let flipDelayKey = "screenSaverFlipDelay"
        static let driftRateKey = "screenSaverDriftRate"
        static let deckDepthKey = "screenSaverDeckDepth"
        static let pileDepthKey = "screenSaverPileDepth"
        static let timelineHoldKey = "screenSaverTimelineHold"
        static let timelineDateSourceKey = "screenSaverTimelineDateSource"
        static let timelineDatePrecisionKey = "screenSaverTimelineDatePrecision"

        private static func detailsKey(for layout: Layout) -> String {
            // Preserves screenSaverPosterFocusDetails and screenSaverBackdropDetails.
            let name = layout.rawValue
            return "screenSaver" + name.prefix(1).uppercased() + name.dropFirst() + "Details"
        }

        var isEnabled = false
        var scope = Scope.favorites
        var layout = Layout.coverWall
        private var detailSelections: [Layout: [Detail]] = [:]
        var interval = ManifestSettings.defaultInterval
        var coverWallRows = ManifestSettings.defaultCoverWallRows
        /// Whether the colour background drifts.
        var washFlows = true
        /// How fast it drifts, as a multiple of the normal speed.
        var washSpeed: Double = 1
        var flipDelay = ManifestSettings.defaultFlipDelay
        var driftRate = ManifestSettings.defaultDriftRate
        var deckDepth = ManifestSettings.defaultDeckDepth
        var pileDepth = ManifestSettings.defaultPileDepth
        var timelineHold = ManifestSettings.defaultTimelineHold
        var timelineDateSource: ScreenSaverManifest.TimelineDateSource = .airDate
        var timelineDatePrecision: ScreenSaverManifest.TimelineDatePrecision = .fullDate

        init() {}

        init(defaults: UserDefaults) {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
            scope = defaults.string(forKey: Self.scopeKey).flatMap(Scope.init(rawValue:)) ?? .favorites
            layout = defaults.string(forKey: Self.layoutKey).flatMap(Layout.init(rawValue:)) ?? .coverWall
            for layout in Layout.allCases where !Detail.available(for: layout).isEmpty {
                if let stored = defaults.stringArray(forKey: Self.detailsKey(for: layout)) {
                    detailSelections[layout] = Detail.normalized(stored.compactMap(Detail.init(rawValue:)))
                }
            }
            let rows = defaults.integer(forKey: Self.coverWallRowsKey)
            if ManifestSettings.coverWallRowRange.contains(rows) { coverWallRows = rows }
            washFlows = defaults.object(forKey: Self.washFlowsKey) as? Bool ?? true
            let speed = defaults.double(forKey: Self.washSpeedKey)
            if ManifestSettings.washSpeeds.contains(speed) { washSpeed = speed }

            func stored<Value: Comparable>(_ key: String, in range: ClosedRange<Value>) -> Value? {
                guard let value = defaults.object(forKey: key) as? Value, range.contains(value) else { return nil }
                return value
            }
            func duration(_ key: String, presets: [TimeInterval], defaultValue: TimeInterval) -> TimeInterval {
                let value = defaults.double(forKey: key)
                return presets.contains(value) ? value : defaultValue
            }
            interval = duration(Self.intervalKey, presets: ManifestSettings.intervalPresets, defaultValue: interval)
            flipDelay = duration(Self.flipDelayKey, presets: ManifestSettings.flipDelayPresets, defaultValue: flipDelay)
            timelineHold = duration(
                Self.timelineHoldKey, presets: ManifestSettings.timelineHoldPresets, defaultValue: timelineHold)
            driftRate = stored(Self.driftRateKey, in: ManifestSettings.driftRateRange) ?? driftRate
            deckDepth = stored(Self.deckDepthKey, in: ManifestSettings.deckDepthRange) ?? deckDepth
            pileDepth = stored(Self.pileDepthKey, in: ManifestSettings.deckDepthRange) ?? pileDepth
            timelineDateSource =
                defaults.string(forKey: Self.timelineDateSourceKey)
                .flatMap(ScreenSaverManifest.TimelineDateSource.init(rawValue:)) ?? .airDate
            timelineDatePrecision =
                defaults.string(forKey: Self.timelineDatePrecisionKey)
                .flatMap(ScreenSaverManifest.TimelineDatePrecision.init(rawValue:)) ?? .fullDate
        }

        func save(to defaults: UserDefaults) {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            defaults.set(scope.rawValue, forKey: Self.scopeKey)
            defaults.set(layout.rawValue, forKey: Self.layoutKey)
            for (layout, details) in detailSelections {
                defaults.set(details.map(\.rawValue), forKey: Self.detailsKey(for: layout))
            }
            defaults.set(interval, forKey: Self.intervalKey)
            defaults.set(coverWallRows, forKey: Self.coverWallRowsKey)
            defaults.set(washFlows, forKey: Self.washFlowsKey)
            defaults.set(washSpeed, forKey: Self.washSpeedKey)
            defaults.set(flipDelay, forKey: Self.flipDelayKey)
            defaults.set(driftRate, forKey: Self.driftRateKey)
            defaults.set(deckDepth, forKey: Self.deckDepthKey)
            defaults.set(pileDepth, forKey: Self.pileDepthKey)
            defaults.set(timelineHold, forKey: Self.timelineHoldKey)
            defaults.set(timelineDateSource.rawValue, forKey: Self.timelineDateSourceKey)
            defaults.set(timelineDatePrecision.rawValue, forKey: Self.timelineDatePrecisionKey)
        }

        var manifestSettings: ManifestSettings {
            .init(
                layout: layout, details: details(for: layout), interval: interval, coverWallRows: coverWallRows,
                washFlows: washFlows, washSpeed: washSpeed, flipDelay: flipDelay, driftRate: driftRate,
                deckDepth: deckDepth, pileDepth: pileDepth, timelineHold: timelineHold,
                timelineDateSource: timelineDateSource, timelineDatePrecision: timelineDatePrecision)
        }

        func details(for layout: Layout) -> [Detail] {
            let layout = layout.detailSelectionLayout
            return detailSelections[layout] ?? Detail.defaults(for: layout)
        }

        mutating func setDetail(_ detail: Detail, _ isOn: Bool, for layout: Layout) {
            let layout = layout.detailSelectionLayout
            guard Detail.available(for: layout).contains(detail) else { return }
            var selected = Set(details(for: layout))
            if isOn { selected.insert(detail) } else { selected.remove(detail) }
            detailSelections[layout] = Detail.normalized(selected)
        }
    }
#endif
