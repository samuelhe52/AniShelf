//
//  AppLifecycleEventGateTests.swift
//  MyAnimeListTests
//
//  Created by Claude Code on behalf of Samuel He on 2026/9/27.
//

import SwiftUI
import Testing

@testable import MyAnimeList

@MainActor
struct AppLifecycleEventGateTests {
    @Test func launchPassesOnceForAllWindows() {
        let gate = AppLifecycleEventGate()

        #expect(gate.shouldHandleLaunch())
        #expect(!gate.shouldHandleLaunch())
    }

    @Test func eachPhaseTransitionPassesOnceAcrossWindowDeliveries() {
        let gate = AppLifecycleEventGate()
        // Two windows deliver every app-level transition.
        let deliveries: [ScenePhase] = [
            .active, .active, .inactive, .inactive, .background, .background, .active, .active
        ]

        let handled = deliveries.filter { gate.shouldHandlePhaseChange(to: $0) }

        #expect(handled == [.active, .inactive, .background, .active])
    }

    @Test func eachKeyChangePassesOnceIncludingRemoval() {
        let gate = AppLifecycleEventGate()
        let deliveries: [String?] = [nil, nil, "key", "key", nil, nil]

        let handled = deliveries.filter { gate.shouldHandleKeyChange(to: $0) }

        #expect(handled == [nil, "key", nil])
    }

    @Test func activationSkipsTheFirstDeliveryThatLaunchCovers() {
        let gate = AppLifecycleEventGate()

        #expect(!gate.shouldHandleActivation())
        #expect(gate.shouldHandleActivation())
        #expect(gate.shouldHandleActivation())
    }

    @Test func windowCoordinatorTracksOpenWindowsByRecentActivation() {
        let windows = AppWindowCoordinator()
        // Before any window registers, every window may present.
        #expect(windows.isPrimary("library-a"))

        windows.register("library-a", role: .library, isActive: true)
        windows.register("library-b", role: .library, isActive: false)
        windows.register("settings", role: .auxiliary, isActive: false)
        #expect(windows.primaryWindowID == "library-a")
        #expect(!windows.isPrimary("library-b"))

        windows.windowDidBecomeActive("settings")
        #expect(windows.primaryWindowID == "settings")
        #expect(windows.frontmostLibraryWindowID == "library-a")
        // Library-only presentations, such as the reminder warning, skip Settings.
        #expect(windows.isFrontmostLibraryWindow("library-a"))

        windows.windowDidBecomeActive("library-b")
        #expect(windows.frontmostLibraryWindowID == "library-b")

        // A closed window hands presentations and routes to the next most recent one.
        windows.unregister("library-b")
        #expect(!windows.isRegistered("library-b"))
        #expect(windows.primaryWindowID == "settings")
        #expect(windows.frontmostLibraryWindowID == "library-a")

        // Activation of an unknown window changes nothing.
        windows.windowDidBecomeActive("library-b")
        #expect(windows.registeredWindowIDs == ["library-a", "settings"])
    }

    #if os(macOS)
        @Test func toastsShowOnlyInTheMostRecentlyActiveWindow() {
            let windows = AppWindowCoordinator()
            let center = ToastCenter(windows: windows)
            #expect(center.presentsToasts(inSceneIdentifier: "window-a"))
            #expect(center.presentsToasts(inSceneIdentifier: "window-b"))

            windows.register("window-a", role: .library, isActive: true)
            windows.register("window-b", role: .library, isActive: false)
            #expect(center.presentsToasts(inSceneIdentifier: "window-a"))
            #expect(!center.presentsToasts(inSceneIdentifier: "window-b"))

            windows.unregister("window-a")
            #expect(center.presentsToasts(inSceneIdentifier: "window-b"))
        }
    #endif
}
