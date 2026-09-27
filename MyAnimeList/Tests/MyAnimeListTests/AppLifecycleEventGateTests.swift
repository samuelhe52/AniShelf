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
}
