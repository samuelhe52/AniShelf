//
//  AppLifecycleEventGate.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/9/27.
//

import SwiftUI

/// Collapses per-window deliveries of app-wide lifecycle events into a single handling.
///
/// The app's root modifiers are attached inside `WindowGroup`, so every open window installs its
/// own copy of them. Each copy observes the same app-level scene phase and shared key storage, so
/// one app event reaches every window. Only the first delivery of each distinct event passes.
@MainActor
final class AppLifecycleEventGate {
    private var hasHandledLaunch = false
    private var lastHandledPhase: ScenePhase?
    private var hasHandledKeyChange = false
    private var lastHandledKey: String?

    /// Passes once per process; later windows appearing are not app launches.
    func shouldHandleLaunch() -> Bool {
        guard !hasHandledLaunch else { return false }
        hasHandledLaunch = true
        return true
    }

    /// Passes the first delivery of each app-level phase transition.
    func shouldHandlePhaseChange(to phase: ScenePhase) -> Bool {
        guard phase != lastHandledPhase else { return false }
        lastHandledPhase = phase
        return true
    }

    /// Passes the first delivery of each TMDb API key change.
    func shouldHandleKeyChange(to key: String?) -> Bool {
        guard !hasHandledKeyChange || key != lastHandledKey else { return false }
        hasHandledKeyChange = true
        lastHandledKey = key
        return true
    }
}
