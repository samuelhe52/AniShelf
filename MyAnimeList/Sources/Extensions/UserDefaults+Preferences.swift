//
//  UserDefaults+Preferences.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/11.
//

import Foundation

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) != nil {
            bool(forKey: key)
        } else {
            defaultValue
        }
    }

    var usesTMDbRelayServer: Bool {
        bool(forKey: .useTMDbRelayServer, defaultValue: true)
    }

    var isLibraryScoringEnabled: Bool {
        bool(forKey: .libraryScoringEnabled, defaultValue: true)
    }
}
