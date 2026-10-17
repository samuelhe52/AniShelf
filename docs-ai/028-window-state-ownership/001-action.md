# 028 — Window state ownership: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-18 | Plan written after the 008.002 audit and the maintainer's ownership decision. | `000-plan.md` |
| 2026-10-18 | Implemented the shared-data race fixes, then the window-owned browse scope, the app window coordinator, and Mac app-level activation. | `8426ef1`, then the following commit on `feat/window-state-ownership` |
| 2026-10-18 | Codex review round 1 (GPT-6.1 Sol, high): three P2 findings fixed. A rejected refresh left What's New spinning. The reminder warning picked an auxiliary window. The first Mac activation skipped the active day. | Review thread `01a14b21-5d6a-70f1-bd79-fd37f2c57e37` |
| 2026-10-18 | A Mac runtime check found that `@SceneStorage` arrives after first appear, so windows were not restoring. Added late restoration. | This record, Deviations |
| 2026-10-18 | Codex review rounds 2–5 hardened late restoration. A user change closes it for good (explicit flags rather than baseline equality). A rejected late value is overwritten with the live value. Untouched windows persist their starting state. The restored selection waits for the restored scope and Find, stops once the user changes selection, scope or Find, and ignores echoes of its own saves. | Same review thread |
| 2026-10-18 | Maintainer visual pass on Mac and iPad: every pending runtime check passed. | This record, Validation |

Committed on `feat/window-state-ownership` at the maintainer's request. Not pushed.

## Outcome and current state (as of 2026-10-18)

**Window-owned browse state.** `LibraryBrowseScope` owns each library window's:

- filters and active category
- sort, sort direction and group
- view style
- 023's memoized display list (`displayItems`, `displayIDs`, `entriesOnDisplay`,
  `displayedEntry(for:)`)
- `filterAndSort`, reveal helpers, the deletion scroll target, and the Mac sidebar
  scope

`LibraryStore` no longer has `filters`, `activeCategoryID` or a display cache. Its
`sortStrategy`, `sortReversed` and `groupStrategy` are now the preferences that seed
new windows; they stay iCloud-synced. A window's sort, group or view-style change
also writes the preference. Remote or other-window preference changes never rewrite
an open window. Changing Default Filters, disabling scoring, or disabling categories
still applies to every open window.

**Scene restoration.** `.libraryBrowseScope()` (`LibraryBrowseScopeHost`) creates
the scope before the root's first render, then saves `LibraryBrowseScope.State` to
`@SceneStorage`. Restoration differs by platform:

- **Mac.** Selection and Find text are stored per scene as well. A window without
  saved state falls back to the shared last-inspected entry, as before.
- **iOS.** The inspector entry is stored per scene, with the same fallback.
- **Late values.** Scene storage that arrives after first appear is applied until
  the user changes that value; after that, the live value overwrites the late one.
  A pending restored selection reapplies only while selection, scope and Find are
  all still untouched.

**App window coordinator.** `AppWindowCoordinator` registers windows through
`providesWindowSceneIdentifier(role:)`.

- **IDs.** Mac windows get a UUID kept as an associated object. iOS keeps the scene
  session's persistent identifier.
- **Liveness.** A window counts as open from registration until `willClose` (Mac)
  or `didDisconnect` (iOS). Visibility no longer matters. A Settings or Support
  window that SwiftUI reopens in the same `NSWindow` re-registers when it becomes
  key.
- **Activation order.** The coordinator records it and provides:
  - `primaryWindowID`, which picks the window for Mac toasts
  - `frontmostLibraryWindowID`, which picks the window for Mac reminder routes and
    Help > What's New
  - `isFrontmostLibraryWindow`, which picks the window for the reminder warning
- **Rerouting.** Airing routes and the What's New claim move to another open window
  when theirs closes. `onOtherWindowSceneClosed`, `ToastCenter`'s own claim, and
  `MacLibraryWindows`' set of IDs are gone.

**Mac lifecycle.** `LibrarySyncNotificationBridge.configureActivation` runs
foreground work on `NSApplication.didBecomeActiveNotification`, with or without a
library window. The first activation records the active day but leaves sync and the
reminder refresh to the launch handler. The window-level `scenePhase` `.active`
branch is iOS-only.

**Shared-data races:**

- `createNewEntry` rechecks both the entry and its parent series after its TMDb
  awaits. It reuses rows another add inserted meanwhile.
- `isRefreshingAllMetadata` on the store blocks overlapping Refresh All runs. A
  rejected request completes its own reporter with "Metadata is already
  refreshing." The Settings row and the Mac menu item are disabled while a refresh
  runs.
- A failed add clears its loading toast.

Key source files:

- `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`
- `MyAnimeList/Sources/Views/Library/LibraryBrowseScopeHost.swift`
- `MyAnimeList/Sources/App/AppWindowCoordinator.swift`
- `MyAnimeList/Sources/Views/Gadgets/WindowSceneIdentifierReader.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- `MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift`
- `MyAnimeList/Sources/Mac/MacLibraryView.swift`,
  `MyAnimeList/Sources/Mac/MacLibraryView+Actions.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore.swift`,
  `MyAnimeList/Sources/ViewModels/Library/LibraryStore+Entries.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryProfileSettingsActions.swift`

## Deviations from plan

- **Mac scene storage arrives late.** The plan assumed `@SceneStorage` is readable
  when the window first appears. On native macOS 27 it arrived about 2 seconds
  later. Logging showed `nil` at `onAppear` and the restored `Data` afterwards, so
  windows reopened with preference-seeded state.
  - The host still restores synchronously when the value is present, as on iOS.
  - A persistence view also applies late values while
    `LibraryBrowseScope.acceptsSceneRestoration` is open (Codex rounds 2–5).
  - Mac Find text and selection use the same pattern, with
    `findAcceptsRestoration` and `selectionAcceptsRestoration`. The selection keeps
    its restored raw IDs pending until the restored scope and Find settle.
- **Reminder warning target.** The plan said "the primary window". It uses the
  most recently active *library* window, because Settings and Support have no
  warning presenter (Codex round 1).
- **First Mac activation.** It records the active day, because the launch handler
  can run before the app is active (Codex round 1).
- **Test seam.** `createNewEntry` gained an optional `latestInfoFetcher`, matching
  `LibraryEntryConverter`, so the concurrent-add race is testable without TMDb
  fixtures.

## Validation

- `make build` (iOS) and `make build-mac` passed after the final changes.
- Focused simulator tests passed:
  `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/LibraryPreferenceDefaultsTests MyAnimeListTests/AppLifecycleEventGateTests MyAnimeListTests/WhatsNewAndRefreshTests MyAnimeListTests/LibraryRelationshipAndConversionTests MyAnimeListTests/MacLibrarySelectionTests'`.
- Full suites passed on the final code:
  - `make test-app-mac`, run after the last change
  - `make test-app-sim`, run before the last change. That change is Mac-only
    (`MacLibraryView+Actions.swift`), and `make build` passed after it.
- `swift format lint` passed on every touched Swift file.
- New or extended tests:
  - two independent scopes, seeding, write-through, and no rewrite on remote
    preference changes (`LibrarySortingAndDeletionTests`)
  - coordinator order, primary and frontmost windows, and unregistration
  - the activation gate
  - the Mac toast window (`AppLifecycleEventGateTests`)
  - What's New release (`WhatsNewAndRefreshTests`)
  - the overlapping refresh rejection (`WhatsNewAndRefreshTests`)
  - concurrent adds of one title and of two seasons sharing a parent
    (`LibraryRelationshipAndConversionTests`)
- Runtime checks with `make run-mac` and `-library-fixture 60`, driven through
  System Events:
  - Two windows held different sidebar scopes ("Watching – 13" beside "All –
    60").
  - Quit and relaunch restored each window's own scope and Find text, after the
    late-restoration fix. This was rechecked on the final build.
  - Closing every window and reopening the app opened a library window.
- Maintainer visual pass, 2026-10-18, on Mac and iPad with a real library. The
  maintainer reported that every check passed:
  - Mac reminder routing with the app hidden, the only library window minimized,
    and no library window open
  - a foreground sync on activation with no library window open
  - toasts in the most recently active window only, the reminder warning in the
    frontmost library window only, and What's New targeting and handoff on close
  - per-window sort, group, view style, selection and window title; a reveal in
    one window leaving the other alone
  - a ⌘⌥N window seeding from preferences and opening on the last-inspected entry
  - the brief preference-seeded scope shown before late restoration, judged
    acceptable
  - Refresh All disabled states and the failed-add toast clearing
  - iPad multi-window: per-window browse state, per-window inspector restoration,
    and toasts in every window

## Open questions

- **Delay cause.** Why native macOS delivers `@SceneStorage` about 2 seconds after
  first appear is unknown. Until it arrives, a restored window can briefly show its
  preference-seeded scope before switching; the maintainer accepted this in the
  visual pass.
- **Backup restore.** A restore reloads preferences, but open windows keep their
  scope and sort. The restored sort and group seed new windows only. This was not
  raised as a problem, but it may be unexpected.
- **Per-window caches.** Each window now computes its own display list. No
  multi-window benchmark was run (docs-ai 026 measures one window).
- **App Intents branch.** `feat/app-intents-spotlight` routes Open Entry through the
  old `MacLibraryWindows` API. It needs to adopt the coordinator when it merges.
