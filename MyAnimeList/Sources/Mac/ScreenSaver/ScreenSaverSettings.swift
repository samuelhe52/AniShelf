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
        static let showsTitlesKey = "screenSaverShowsTitles"
        static let intervalKey = "screenSaverInterval"

        var isEnabled = false
        var scope = Scope.favorites
        var layout = ScreenSaverManifest.Layout.coverWall
        var showsTitles = true
        var interval: TimeInterval = 12

        init() {}

        init(defaults: UserDefaults) {
            isEnabled = defaults.bool(forKey: Self.enabledKey)
            scope = defaults.string(forKey: Self.scopeKey).flatMap(Scope.init(rawValue:)) ?? .favorites
            layout =
                defaults.string(forKey: Self.layoutKey).flatMap(ScreenSaverManifest.Layout.init(rawValue:))
                ?? .coverWall
            showsTitles = defaults.bool(forKey: Self.showsTitlesKey, defaultValue: true)
            let seconds = defaults.double(forKey: Self.intervalKey)
            if seconds.isFinite, (1...3_600).contains(seconds) { interval = seconds }
        }

        func save(to defaults: UserDefaults) {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            defaults.set(scope.rawValue, forKey: Self.scopeKey)
            defaults.set(layout.rawValue, forKey: Self.layoutKey)
            defaults.set(showsTitles, forKey: Self.showsTitlesKey)
            defaults.set(interval, forKey: Self.intervalKey)
        }

        var manifestSettings: ScreenSaverManifest.Settings {
            .init(layout: layout, showsTitles: showsTitles, interval: interval)
        }
    }
#endif
