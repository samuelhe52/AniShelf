//
//  ScreenSaverPlaybackOptions.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/21.
//

/// Playback options for testing layouts with the Screen Saver Demo.
public struct ScreenSaverPlaybackOptions: Equatable, Sendable {
    /// Play only this many entries, to try small libraries.
    public let entryLimit: Int?
    /// Fix the shuffle so configurations can be compared on the same entries.
    public let seed: UInt64?
    /// Speed up animation and pauses. 1 is real time.
    public let timeScale: Double

    public init(entryLimit: Int? = nil, seed: UInt64? = nil, timeScale: Double = 1) {
        self.entryLimit = entryLimit
        self.seed = seed
        self.timeScale = timeScale.isFinite ? max(timeScale, 0.05) : 1
    }
}
