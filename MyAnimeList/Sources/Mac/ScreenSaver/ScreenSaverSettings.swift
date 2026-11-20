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
        enum Scope: String, CaseIterable {
            case favorites
            case watched
            case all

            func includes(_ entry: AnimeEntry) -> Bool {
                switch self {
                case .favorites: entry.favorite
                case .watched: entry.watchStatus == .watched
                case .all: true
                }
            }
        }

        static let enabledKey = "screenSaverEnabled"
        static let scopeKey = "screenSaverScope"
        static let layoutKey = "screenSaverLayout"
        static let posterFocusDetailsKey = "screenSaverPosterFocusDetails"
        static let backdropDetailsKey = "screenSaverBackdropDetails"
        static let intervalKey = "screenSaverInterval"
        static let coverWallRowsKey = "screenSaverCoverWallRows"

        var isEnabled = false
        var scope = Scope.favorites
        var layout = ScreenSaverManifest.Layout.coverWall
        var posterFocusDetails = ScreenSaverManifest.Detail.defaults(for: .posterFocus)
        var backdropDetails = ScreenSaverManifest.Detail.defaults(for: .backdrop)
        var interval: TimeInterval = 12
        var coverWallRows = ScreenSaverManifest.Settings.defaultCoverWallRows

        init() {}

        init(defaults: UserDefaults) {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
            scope = defaults.string(forKey: Self.scopeKey).flatMap(Scope.init(rawValue:)) ?? .favorites
            layout =
                defaults.string(forKey: Self.layoutKey).flatMap(ScreenSaverManifest.Layout.init(rawValue:))
                ?? .coverWall
            if let stored = defaults.stringArray(forKey: Self.posterFocusDetailsKey) {
                posterFocusDetails = ScreenSaverManifest.Detail.normalized(
                    stored.compactMap(ScreenSaverManifest.Detail.init))
            }
            if let stored = defaults.stringArray(forKey: Self.backdropDetailsKey) {
                backdropDetails = ScreenSaverManifest.Detail.normalized(
                    stored.compactMap(ScreenSaverManifest.Detail.init))
            }
            let seconds = defaults.double(forKey: Self.intervalKey)
            if seconds.isFinite, (1...3_600).contains(seconds) { interval = seconds }
            let rows = defaults.integer(forKey: Self.coverWallRowsKey)
            if ScreenSaverManifest.Settings.coverWallRowRange.contains(rows) { coverWallRows = rows }
        }

        func save(to defaults: UserDefaults) {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            defaults.set(scope.rawValue, forKey: Self.scopeKey)
            defaults.set(layout.rawValue, forKey: Self.layoutKey)
            defaults.set(posterFocusDetails.map(\.rawValue), forKey: Self.posterFocusDetailsKey)
            defaults.set(backdropDetails.map(\.rawValue), forKey: Self.backdropDetailsKey)
            defaults.set(interval, forKey: Self.intervalKey)
            defaults.set(coverWallRows, forKey: Self.coverWallRowsKey)
        }

        var manifestSettings: ScreenSaverManifest.Settings {
            .init(layout: layout, details: details(for: layout), interval: interval, coverWallRows: coverWallRows)
        }

        func details(for layout: ScreenSaverManifest.Layout) -> [ScreenSaverManifest.Detail] {
            switch layout {
            // Cover Wall's fallback for small libraries is Poster Focus.
            case .coverWall, .posterFocus: posterFocusDetails
            case .backdrop: backdropDetails
            }
        }

        mutating func setDetail(
            _ detail: ScreenSaverManifest.Detail, _ isOn: Bool, for layout: ScreenSaverManifest.Layout
        ) {
            var selected = Set(details(for: layout))
            if isOn { selected.insert(detail) } else { selected.remove(detail) }
            let normalized = ScreenSaverManifest.Detail.normalized(selected)
            switch layout {
            case .coverWall, .posterFocus: posterFocusDetails = normalized
            case .backdrop: backdropDetails = normalized
            }
        }
    }
#endif
