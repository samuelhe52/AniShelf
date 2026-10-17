//
//  LibraryEntryRouter.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/18.
//

import Observation

/// A request from outside the library to open one entry's detail.
struct LibraryEntryRoute: Equatable {
    let entryIdentityRawID: String
    /// Persistent identifier of the scene that should open the entry.
    /// `nil` lets whichever library window claims the route first open it.
    let targetSceneIdentifier: String?
}

/// Hands entries opened from outside the library to exactly one library window.
///
/// Airing-reminder notifications use it on both platforms, and the Open Entry intent uses it
/// on macOS, where `onAppIntentExecution` is unavailable. Each window claims the pending route
/// through `libraryWindowBehaviors`.
@MainActor
@Observable
final class LibraryEntryRouter {
    static let shared = LibraryEntryRouter()

    private(set) var pendingRoute: LibraryEntryRoute?

    func requestEntry(_ entryIdentityRawID: String, inSceneIdentifiedBy targetSceneIdentifier: String?) {
        pendingRoute = LibraryEntryRoute(
            entryIdentityRawID: entryIdentityRawID,
            targetSceneIdentifier: targetSceneIdentifier
        )
    }

    /// Consumes the pending route when it belongs to the given scene, so exactly one window opens it.
    ///
    /// A route whose target scene has disconnected falls back to any window.
    func claimPendingRoute(
        forSceneIdentifier sceneIdentifier: String?,
        isSceneConnected: (String) -> Bool
    ) -> String? {
        guard let pendingRoute else { return nil }
        if let targetSceneIdentifier = pendingRoute.targetSceneIdentifier,
            isSceneConnected(targetSceneIdentifier)
        {
            guard sceneIdentifier == targetSceneIdentifier else { return nil }
        }
        self.pendingRoute = nil
        return pendingRoute.entryIdentityRawID
    }
}
