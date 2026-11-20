//
//  ScreenSaverSession.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation

struct ScreenSaverSession {
    private var activeToken: UUID?

    mutating func start() -> UUID {
        let token = UUID()
        activeToken = token
        return token
    }

    mutating func stop() {
        activeToken = nil
    }

    func contains(_ token: UUID) -> Bool {
        activeToken == token
    }
}
