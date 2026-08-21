//
//  TVMazeConfirmedMappingStore.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/8/11.
//

import Foundation

struct TVMazeConfirmedMappingReplacement: Equatable, Sendable {
    let tmdbSeriesID: Int
    let previousShowID: Int
    let newShowID: Int
}

enum TVMazeConfirmedMappingWriteResult: Equatable, Sendable {
    case inserted
    case unchanged
    case replaced(TVMazeConfirmedMappingReplacement)
    case rejected
}

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

    @discardableResult
    func confirm(
        showID: Int,
        forTMDbSeriesID tmdbSeriesID: Int
    ) -> TVMazeConfirmedMappingWriteResult {
        guard tmdbSeriesID > 0, showID > 0 else { return .rejected }

        var mappings = mappings
        let previousShowID = mappings[String(tmdbSeriesID)]
        guard previousShowID != showID else { return .unchanged }

        mappings[String(tmdbSeriesID)] = showID
        defaults.set(mappings, forKey: Key.showIDsByTMDbSeriesID)

        guard let previousShowID else { return .inserted }
        return .replaced(
            TVMazeConfirmedMappingReplacement(
                tmdbSeriesID: tmdbSeriesID,
                previousShowID: previousShowID,
                newShowID: showID
            )
        )
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
