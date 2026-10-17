//
//  LibraryEntryRouterTests.swift
//  MyAnimeListTests
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/18.
//

import Testing

@testable import MyAnimeList

@MainActor
struct LibraryEntryRouterTests {
    @Test func routeIsClaimedOnlyByTargetSceneUnlessItDisconnected() {
        let router = LibraryEntryRouter()
        let connected: (String) -> Bool = { $0 == "target" }

        router.requestEntry("entry", inSceneIdentifiedBy: "target")
        #expect(router.claimPendingRoute(forSceneIdentifier: nil, isSceneConnected: connected) == nil)
        #expect(router.claimPendingRoute(forSceneIdentifier: "other", isSceneConnected: connected) == nil)
        #expect(router.claimPendingRoute(forSceneIdentifier: "target", isSceneConnected: connected) == "entry")
        #expect(router.claimPendingRoute(forSceneIdentifier: "target", isSceneConnected: connected) == nil)

        router.requestEntry("entry", inSceneIdentifiedBy: "closed")
        #expect(router.claimPendingRoute(forSceneIdentifier: "other", isSceneConnected: connected) == "entry")
    }
}
