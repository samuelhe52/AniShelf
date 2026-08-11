//
//  TVMazeConfirmedMappingStore.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/8/11.
//

import Foundation

/// Persists user-confirmed TMDb-series-to-TVMaze-show identity mappings.
///
/// The actor serializes updates to the shared dictionary so concurrent resolutions do not
/// overwrite one another. Provider responses and schedules remain outside this store.
actor TVMazeConfirmedMappingStore {
    static let shared = TVMazeConfirmedMappingStore()

    private enum Key {
        static let showIDsByTMDbSeriesID = "TVMaze.confirmedShowIDsByTMDbSeriesID"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func showID(forTMDbSeriesID tmdbSeriesID: Int) -> Int? {
        guard tmdbSeriesID > 0 else { return nil }
        return mappings[String(tmdbSeriesID)]
    }

    func confirm(showID: Int, forTMDbSeriesID tmdbSeriesID: Int) {
        guard tmdbSeriesID > 0, showID > 0 else { return }

        var mappings = mappings
        mappings[String(tmdbSeriesID)] = showID
        defaults.set(mappings, forKey: Key.showIDsByTMDbSeriesID)
    }

    private var mappings: [String: Int] {
        guard let storedValues = defaults.dictionary(forKey: Key.showIDsByTMDbSeriesID) else {
            return [:]
        }

        return storedValues.reduce(into: [:]) { result, element in
            guard let showID = element.value as? Int else { return }
            result[element.key] = showID
        }
    }
}
