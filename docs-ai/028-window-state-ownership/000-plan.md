# 028 — Window state ownership: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — maintainer accepted |
| Anchor date | 2026-10-18 |
| Origin | Maintainer, 2026-10-18, after the multi-window audit in [008.002](../008-multi-window-presentation/002-audit-backlog.md). The maintainer observed that several audit findings, and most of the "intended caveats", come from state shared between windows that should not be shared. Claude Code and a Codex review session (GPT-6.1 Sol) converged on the model below; the maintainer accepted the defaults for the three open decisions. |
| Related | [008 multi-window presentation](../008-multi-window-presentation/000-plan.md), [023 library display cache](../023-library-display-cache/000-plan.md), [021 Mac selection model](../021-mac-selection-model/000-plan.md), [020 native macOS](../020-native-macos/000-plan.md) |

## Background

Entry 008 decided which state is shared across windows and which is per window.
It shared the browse scope: filters, active category, sort, group and view style.
It also shared the last-inspected entry, and attached app-wide lifecycle work and
presentations to every window, deduplicating them with gates and claims.

The 2026-10-18 audit showed that these choices cause most of the multi-window
defects and caveats:

- **Window state stored app-wide.** Revealing an entry in one window (Show Details,
  add from search, a reminder route) resets the filters or category in every
  window. Other windows then prune their selections, and every Mac window shows
  the same title. Every restored window opens on the same last-inspected entry.
- **App-wide behavior attached to windows.** Launch and foreground handling run
  from window content, so on the Mac nothing reacts to activation while no library
  window is open. Toast and What's New claims and reminder routes depend on
  windows claiming them. They use an address-derived window ID that can repeat,
  a registry that never forgets closed windows, and `isVisible` as liveness, which
  is wrong for hidden apps and minimized windows.

Two further findings are races on truly shared data, and scoping does not fix
them. Concurrent adds can create duplicate entries or duplicate parent series.
Refresh All Metadata can run several times at once. A failed add also leaves the
loading toast on screen.

## Goals

- Give every piece of library state one explicit owner:
  - app/data
  - window
  - an app-owned window coordinator
- Make the browse scope, view style, selection and inspector state window-owned,
  and restore them per scene.
- Replace address-derived Mac window IDs and the visibility-based registry with
  one app-owned coordinator. The coordinator tracks windows by stable ID, records
  activation order, unregisters on close, and picks target windows.
- Run app-wide lifecycle work once per app event, independent of how many library
  windows are open.
- Fix the two shared-data races and the stuck loading toast.

### Non-goals

- **Edit ownership across windows (008.002 P1)** is archived by maintainer
  decision on 2026-10-18. It requires two windows on the same entry plus Discard,
  which is unlikely.
- **General robustness items from 008.002** stay out of scope, except the failed-add
  toast:
  - stale open-detail metadata
  - workflows holding model objects
  - backup-restore invalidation
- **No change to:**
  - the iOS toast policy (toasts show in every iPad window, a 2026-09-27 decision)
  - the iCloud conflict alert in Settings
- **No merge of `feat/app-intents-spotlight`.** Its Open Entry route should adopt
  the coordinator when it merges.

## Ownership model

| Owner | Holds | Persistence |
| --- | --- | --- |
| App / data (`LibraryStore`, preferences) | Entries, categories, preferences, cloud sync, reminders, app-wide operations | SwiftData, UserDefaults, iCloud-synced settings |
| Window (`LibraryBrowseScope`, root view state) | Filters, active category, sort, group, sort direction, view style, display cache, selection, Mac Find text, inspector entry | `@SceneStorage`; new windows seed from preferences |
| App window coordinator (`AppWindowCoordinator`) | Registered windows by stable ID, activation order, the primary window, routing targets | Memory only |

Sort, group, sort direction and view style remain preferences, and the iCloud-synced
settings keep carrying them. A change in a window also writes the preference, so
the latest choice seeds the next new window and other devices. A preference change
from elsewhere, whether iCloud or another window, does **not** rewrite open windows.

## Design / approach

### Window-owned browse scope

- **New type.** `LibraryBrowseScope` is an `@Observable @MainActor` class, one per
  library window
  (proposed: `MyAnimeList/Sources/ViewModels/Library/LibraryBrowseScope.swift`).
  - It owns the filters, active category ID, sort strategy, sort direction, group
    strategy and view style.
  - It owns the memoized display list (`displayItems`, `displayIDs`,
    `entriesOnDisplay`, `displayedEntry(for:)`). This moves 023's cache out of
    `LibraryStore`, with the same contract: `withObservationTracking`
    invalidation, lazy recompute, unsaved-entry mutations included, and
    selection-independent computation.
  - It owns `filterAndSort`, `canRevealEntry`, `resetFiltersToReveal`,
    `activeCategory` and the Mac sidebar scope.
- **Shared inputs.** The scope reads the library, categories, `categoriesEnabled`
  and `hideDroppedByDefault` from the store. A deleted or disabled category reads
  as All.
- **Persistence.** `LibraryBrowseScope.State` is a `Codable` value. It is persisted
  per scene through `@SceneStorage` by a small host view
  (`LibraryBrowseScopeHost`), which creates the scope before the root's first
  render.
  - Restored state wins.
  - Otherwise the scope seeds from preferences: filters from `defaultFilters`, no
    category, and sort, group, direction and view style from the stored
    preferences.
- **Write-through and defaults.** Changing sort, group, direction or view style in
  a window writes the preference too. Changing Default Filters in Settings applies
  the new defaults to every open window, as it does today, because it is an
  explicit "apply" action. Disabling scoring resets a window grouped by score.
- **Deletion scroll target.** `LibraryStore.deleteEntry(_:updateScrolledID:)`
  takes the window's display order instead of reading a store display list.

### Window-scoped restoration

- **Mac.** Selection and Find text are stored per scene. The shared
  last-inspected entry remains the fallback for a window with no scene state,
  such as ⌘⌥N or the first launch after an update.
- **iOS.** The inspector-detail identity is stored per scene, with the same shared
  fallback.

### App window coordinator

`AppWindowCoordinator` is an `@Observable @MainActor` singleton
(proposed: `MyAnimeList/Sources/App/AppWindowCoordinator.swift`).

- **Stable IDs.** On the Mac, `NSWindow.sceneIdentifier` becomes a UUID kept on
  the window as an associated object. iOS keeps
  `UISceneSession.persistentIdentifier`.
- **Registration.** `providesWindowSceneIdentifier(role:)` registers a window with
  a role (`library` or `auxiliary`) once its ID resolves.
- **Unregistration.** On the Mac, the coordinator unregisters a window on
  `NSWindow.willCloseNotification`. On iOS it unregisters on
  `UIScene.didDisconnectNotification`.
- **Activation order.** The coordinator records activation from key-window changes
  on the Mac (mapping a sheet to its parent) and from scene activation on iOS.
- **Queries:**
  - `isRegistered`
  - `primaryWindowID`: the most recently active registered window
  - `frontmostLibraryWindowID`: the most recently active library window
- **Consumers.**

  | Consumer | Change |
  | --- | --- |
  | Airing-reminder routes | Liveness is registration, not visibility. A route targeting a closed window falls back by observing the registered-window set, which replaces `onOtherWindowSceneClosed`. The Mac picks its target with `frontmostLibraryWindowID`, so hidden apps and minimized windows reuse an existing window instead of opening a new one. |
  | Toasts (Mac) | Show only in `primaryWindowID`. This replaces `ToastCenter.presentingSceneIdentifier`. |
  | What's New | The claim is released when its window unregisters, so another window can take it. |
  | Reminder warning alert | Shows only in the primary window, on both platforms. |
  | Duplicate repair | Keeps blocking every window, by maintainer decision on 2026-10-18. The resolution stays store-owned and serialized. |

### App-lifetime lifecycle

- **Mac activation.** The app delegate handles foreground work on
  `NSApplication.didBecomeActiveNotification`: sync, reminder refresh, active-day
  recording and the TMDb key retry. It reuses the existing sleep/wake pattern and
  works with zero library windows.
  - The first activation is skipped, because the launch handler already covers it.
  - The window-level `scenePhase` `.active` branch stays iOS-only.
- **Background flush.** The background flush and the iOS paths are unchanged.

### Shared-data race fixes

- **Concurrent adds.** `LibraryStore.createNewEntry` rechecks the requested
  identity, and the parent series identity, after its network awaits and before
  inserting.
  - If the entry appeared meanwhile, the existing row wins.
  - If the parent series appeared, the season attaches to it instead of a newly
    generated parent.

  Because the store is main-actor isolated and nothing suspends between the
  recheck and the insert, this closes the race without coalescing tasks.
- **Refresh All guard.** The store owns `isRefreshingAllMetadata`.
  `performRefreshInfos` refuses to start while it is set, and the Settings and Mac
  menu entry points are disabled.
- **Failed add.** A failed add clears its loading toast.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Per-window sort, group and view style | Maintainer decision, 2026-10-18 (default accepted). They are browse state like filters. Rejected: keeping them as live shared preferences, which keeps windows interfering. |
| New windows seed from restored scene state, then preferences | Maintainer decision, 2026-10-18 (default accepted). Rejected: copying the active window, which would be an explicit Duplicate Window feature. |
| Duplicate repair blocks every window | Maintainer decision, 2026-10-18 (default accepted). The library is unusable until the repair, and one store-owned resolution serializes it. |
| Window presenters stay attached to windows | Codex review: sheets and alerts need a host window. The defects came from duplicated ownership and missing teardown, not from attachment. |
| Small coordinator, not a general event router | Codex review: centralizing registration, targeting and release covers the defects. Feature presenters keep their own policies. Rejected: a generic routed-event bus. |
| Display cache per window | It follows ownership. With N windows, a shared edit triggers N filter and sort passes. That is accepted until measured otherwise. Rejected for now: a shared cache keyed by scope, which adds complexity before any evidence. |
| Recheck before insert instead of coalescing adds | Main-actor isolation makes the recheck atomic with the insert. Coalescing would also save a duplicate TMDb fetch, but it adds task bookkeeping for a rare case. |
| Associated-object UUID for Mac windows | It is stable for the window's lifetime and never reused. Rejected: SwiftUI's `NSWindow.identifier` strings, whose uniqueness is not documented. |

## Validation and acceptance criteria

- **Unit tests** (extend existing suites):
  - Scope filtering, sorting, categories, the reveal reset and cache invalidation
    move from store-level to scope-level tests
    (`LibrarySortingAndDeletionTests`, `LibraryEntryInteractionStateTests`,
    `LibraryPreferenceDefaultsTests`).
  - Two scopes over one store stay independent.
  - A remote preference change does not rewrite an open scope.
  - Window writes update the preference seed.
  - Coordinator registration, unregistration, activation order and the primary
    window.
  - Route fallback after unregistration.
  - What's New release.
  - Concurrent adds of one identity, and of two seasons of one series, produce one
    row each.
  - The Refresh All guard.
- **Builds:** `make build` and `make build-mac`. Run focused tests with
  `make test-app-sim APP_TEST_ONLY=…` on an already booted simulator, plus
  `make test-mac`.
- **Runtime:** `make run-mac` with two windows.
  - Each window keeps its own scope, sort, view style, selection and Find.
  - Reveal in one window leaves the other alone.
  - Close and relaunch restores each window.
  - Toasts and the warning alert appear only in the primary window.
  - Reminder routing with the app hidden, the only window minimized, and no
    library window open.
  - Activation with no library window runs a foreground sync.
- **Review:** Codex (GPT-6.1 Sol, high) reviews the design and the diff.

## Amendments

None yet. Deviations found during implementation, most importantly late Mac scene
storage, are recorded in [001-action.md](001-action.md).
