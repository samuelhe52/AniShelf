//
//  LibraryBrowseScopeHost.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/18.
//

import SwiftUI

extension View {
    /// Gives this window its own `LibraryBrowseScope`, restored from and saved to the scene.
    func libraryBrowseScope() -> some View {
        LibraryBrowseScopeHost { self }
    }
}

/// Creates the window's browse scope before the library root first renders, so a window whose
/// scene state is already restored, as on iOS, never flashes the preference-seeded state.
fileprivate struct LibraryBrowseScopeHost<Content: View>: View {
    @Environment(LibraryStore.self) private var store
    @SceneStorage("libraryBrowseScope") private var storedState: Data?
    @State private var scope: LibraryBrowseScope?
    let content: () -> Content

    var body: some View {
        if let scope {
            content()
                .environment(scope)
                .background {
                    LibraryBrowseScopePersistence(scope: scope, storedState: $storedState)
                }
        } else {
            Color.clear
                .onAppear {
                    let restored = storedState.flatMap {
                        try? JSONDecoder().decode(LibraryBrowseScope.State.self, from: $0)
                    }
                    let scope = LibraryBrowseScope(store: store, restoring: ignoresSceneState ? nil : restored)
                    // Late Mac restoration is refused too; the live state then overwrites it.
                    if ignoresSceneState { scope.acceptsSceneRestoration = false }
                    self.scope = scope
                }
        }
    }

    /// A fixture launch starts from its launch-argument preferences, not the window state a
    /// previous run left behind, so benchmarks always measure the requested layout.
    private var ignoresSceneState: Bool {
        #if DEBUG || LIBRARY_FIXTURES
            LibraryFixture.active != nil
        #else
            false
        #endif
    }
}

/// Saves the scope's state and applies scene state restored late; kept apart so a scope change
/// does not re-render the host.
fileprivate struct LibraryBrowseScopePersistence: View {
    let scope: LibraryBrowseScope
    @Binding var storedState: Data?
    @Environment(LibraryStore.self) private var store
    @AppStorage(.libraryScoringEnabled) private var scoringEnabled = true

    /// The state the window started with or last restored.
    ///
    /// A scope change to anything else is the user's (or Settings'), which closes late
    /// restoration for good.
    @State private var lastAppliedState: LibraryBrowseScope.State?

    var body: some View {
        Color.clear
            // Saving the starting state right away keeps a window that is never edited from
            // reseeding from later preference changes. On the Mac a pending restoration still
            // replaces it.
            .onChange(of: scope.state, initial: true) { _, state in
                if let lastAppliedState, state != lastAppliedState { scope.acceptsSceneRestoration = false }
                if lastAppliedState == nil { lastAppliedState = state }
                storedState = try? JSONEncoder().encode(state)
            }
            // The Mac restores scene storage a moment after the window appears, so the scope
            // may have been seeded from preferences first. A value that arrives after the user
            // changed the scope is replaced with the live state, so it cannot win at relaunch.
            // Echoes of this view's own writes match the scope and change nothing.
            .onChange(of: storedState) { _, data in
                guard let data,
                    let state = try? JSONDecoder().decode(LibraryBrowseScope.State.self, from: data),
                    state != scope.state
                else { return }
                if scope.acceptsSceneRestoration {
                    scope.restore(state)
                    lastAppliedState = scope.state
                } else {
                    storedState = try? JSONEncoder().encode(scope.state)
                }
            }
            // Changing Default Filters in Settings applies them to every open window.
            .onChange(of: store.defaultFilters) { scope.applyDefaultFilters() }
            .onChange(of: scoringEnabled) { _, isEnabled in
                guard !isEnabled, scope.groupStrategy == .score else { return }
                scope.groupStrategy = .none
            }
            .onChange(of: store.categoriesEnabled) { _, isEnabled in
                if !isEnabled { scope.activeCategoryID = nil }
            }
            .accessibilityHidden(true)
    }
}
