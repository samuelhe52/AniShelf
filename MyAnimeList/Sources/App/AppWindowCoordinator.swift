//
//  AppWindowCoordinator.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/18.
//

import Observation
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The app's open windows: which exist, which kind each is, and which was active most
/// recently (docs-ai 028).
///
/// App-wide events that need one window, such as an airing-reminder route, toasts on the Mac,
/// What's New, and the reminder warning, pick their window here instead of every window
/// claiming them. A window counts as open from registration until it closes, whether or not
/// it is visible, so a hidden app or a minimized window still receives routes.
@Observable @MainActor
final class AppWindowCoordinator {
    enum Role: Equatable {
        /// A library window, which can show entries.
        case library
        /// Settings, Support, and other windows that only show app-wide presentations.
        case auxiliary
    }

    static let shared = AppWindowCoordinator(observesPlatformEvents: true)

    private(set) var roles: [String: Role] = [:]
    /// Registered windows, most recently active first.
    private(set) var activationOrder: [String] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(observesPlatformEvents: Bool = false) {
        if observesPlatformEvents { observePlatformEvents() }
    }

    /// The registered windows, observed by views that reroute work when one closes.
    var registeredWindowIDs: Set<String> { Set(roles.keys) }

    /// The most recently active window, which shows app-wide presentations.
    var primaryWindowID: String? { activationOrder.first }

    /// The most recently active library window.
    var frontmostLibraryWindowID: String? {
        activationOrder.first { roles[$0] == .library }
    }

    func isRegistered(_ identifier: String) -> Bool {
        roles[identifier] != nil
    }

    /// Whether the window shows app-wide presentations: the primary one, or every window
    /// before any has registered.
    func isPrimary(_ identifier: String?) -> Bool {
        guard let primaryWindowID else { return true }
        return identifier == primaryWindowID
    }

    /// Whether the window is the most recently active library window, or any library window
    /// before one has registered.
    func isFrontmostLibraryWindow(_ identifier: String?) -> Bool {
        guard let frontmostLibraryWindowID else { return true }
        return identifier == frontmostLibraryWindowID
    }

    /// Adds a window once its identifier resolves. A window that is already active becomes
    /// primary; otherwise it ranks last until it activates.
    func register(_ identifier: String, role: Role, isActive: Bool) {
        roles[identifier] = role
        if isActive {
            windowDidBecomeActive(identifier)
        } else if !activationOrder.contains(identifier) {
            activationOrder.append(identifier)
        }
    }

    func unregister(_ identifier: String) {
        guard roles.removeValue(forKey: identifier) != nil else { return }
        activationOrder.removeAll { $0 == identifier }
    }

    func windowDidBecomeActive(_ identifier: String) {
        guard isRegistered(identifier), activationOrder.first != identifier else { return }
        activationOrder.removeAll { $0 == identifier }
        activationOrder.insert(identifier, at: 0)
    }

    private func observePlatformEvents() {
        let center = NotificationCenter.default
        #if os(macOS)
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) {
                    notification in
                    // Posted on the main queue; the window is only touched there.
                    let window = notification.object as? NSWindow
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        // A sheet or panel stands for the window it is attached to.
                        let hostWindow = window.sheetParent ?? window
                        // A reopened single window (Settings, Support) can reuse its NSWindow
                        // without its content moving to a new window, so re-register it here.
                        if let role = hostWindow.appWindowRole, !self.isRegistered(hostWindow.sceneIdentifier) {
                            self.register(hostWindow.sceneIdentifier, role: role, isActive: true)
                        } else {
                            self.windowDidBecomeActive(hostWindow.sceneIdentifier)
                        }
                    }
                },
                center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
                    notification in
                    let window = notification.object as? NSWindow
                    MainActor.assumeIsolated {
                        guard let window else { return }
                        self.unregister(window.sceneIdentifier)
                    }
                }
            ]
        #else
            observers = [
                center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) {
                    notification in
                    // Posted on the main queue; the scene is only touched there.
                    let scene = notification.object as? UIScene
                    MainActor.assumeIsolated {
                        guard let scene else { return }
                        self.windowDidBecomeActive(scene.session.persistentIdentifier)
                    }
                },
                center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) {
                    notification in
                    let scene = notification.object as? UIScene
                    MainActor.assumeIsolated {
                        guard let scene else { return }
                        self.unregister(scene.session.persistentIdentifier)
                    }
                }
            ]
        #endif
    }
}
