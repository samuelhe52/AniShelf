# 008.002 — Multi-window audit backlog

| Field | Value |
| --- | --- |
| Status | Resolved by [028](../028-window-state-ownership/000-plan.md), except the archived and out-of-scope items below |
| Date | 2026-10-18 |
| Origin | Maintainer asked for an audit of multi-window behavior. Claude Code and a Codex session audited it separately, then merged the results into this list. |

## Context

Entry 008 enabled multiple scenes and scoped presentations to the invoking window.
Since then, the native macOS app (entry [020](../020-native-macos/000-plan.md))
added its own window model: a library `WindowGroup`, separate About, Support and
Settings windows, `MacLibraryWindows`, and address-derived `NSWindow.sceneIdentifier`
values. The audit checked whether 008's boundary between shared state and
per-window state still holds on both platforms.

**Evidence levels.** Most findings come from reading source. Two were reproduced
by Codex with in-memory probes that were not committed:

- stale session baselines
- concurrent duplicate adds

The audit included no full two-window runtime pass. An earlier smoke pass
confirmed that selection and Find are per window and that the sidebar scope is
shared. It did not cover the cases below.

## Change

**Update, same day.** The maintainer archived the P1 edit-ownership item: it needs two
windows on the same entry plus Discard, which is unlikely. They also noted that most
findings, and most of the "intended caveats" below, come from window state that was
shared app-wide. Entry [028](../028-window-state-ownership/000-plan.md) redesigns
state ownership instead of patching each item:

- browse state becomes window-owned
- an app window coordinator replaces the address-based registry and the claim logic
- Mac activation moves to the app delegate

It also includes the concurrent-add, Refresh All and failed-add-toast fixes. The list
below is kept as the audit's original record; for what shipped, see 028's action
record.

Planned work at audit time, in priority order. Each P1/P2 item was meant to be a
separate fix.

### P1 — Session edit ownership

`EntryDetailSession` records `originalUserInfo` once, when it opens
(`MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`). Edits write
directly to the shared `AnimeEntry`, so another window's saved edits look like
this session's unsaved changes.

- On iPad, Discard Changes restores the whole snapshot, including tracking clocks
  (`discardUserEdits` in
  `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`).
- On Mac, Revert Notes restores `originalNotes`
  (`MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailMacTrackingRows.swift`).
- The notes-confirmation check uses the same stale baseline.

Codex reproduced the overwrite with in-memory probes.

**Direction:** track the edits this session made, and detect writes from
elsewhere. Rejected: simply refreshing the baseline when another window saves.
That would also discard this session's ability to undo its own changes.

### P1 — Concurrent adds create duplicates

`createNewEntry` (`MyAnimeList/Sources/ViewModels/Library/LibraryStore+Entries.swift`)
works in three steps:

1. Checks whether the entry exists.
2. Awaits TMDb (`latestInfo`, and `generateParentSeriesEntryForSeason` for
   seasons).
3. Inserts the entry.

Two windows adding the same title both pass step 1. Adding two seasons of the same
show at once can also create two parent-series rows. Duplicates then block sync
until duplicate repair runs. Codex reproduced the duplicate deterministically.

**Direction:** coalesce in-flight adds by identity, and recheck just before
inserting. Apply this to both the requested entry and the helper parent's own
identity. Coalescing child identities alone does not protect two different
seasons.

### P2 — Mac window registry and notification routing

Three source defects (`MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift`,
`MyAnimeList/Sources/Views/Gadgets/WindowSceneIdentifierReader.swift`):

- `NSWindow.sceneIdentifier` is derived from the object address. A window
  allocated later can reuse it.
- `MacLibraryWindows.sceneIdentifiers` never removes closed windows. A later
  About, Support or Settings window could be mistaken for a library window.
  This misrouting was not reproduced.
- `MacLibraryWindows.frontmost` and `WindowScenes.canReceiveRoute` treat
  `isVisible` as liveness.

**Likely defect:** clicking an airing-reminder notification while the app is
hidden (⌘H) opens an extra library window. A hidden app's windows are neither
visible nor miniaturized, so `frontmost` returns nil and `openNew()` runs. Whether
this happens on every click depends on whether macOS unhides the app before
delivering the callback.

**Direction:**

- Give each window a UUID-based identifier.
- Unregister windows on close.
- Decide whether a window still exists separately from whether it is on screen.

### P2 — Mac app activation without a library window

The launch, `scenePhase` and API-key handlers are attached inside the library
window content (`MyAnimeList/Sources/App/MyAnimeListApp.swift`). On Mac the app
keeps running after the last window closes
(`applicationShouldTerminateAfterLastWindowClosed` returns false). With no library
window open:

- re-activating the app triggers no foreground sync or reminder refresh;
- reopening a window does not catch up, because the launch gate has already fired.

This needs runtime confirmation.

**Direction:** handle activation for the app's whole lifetime, following
`configureSleepAndWake`.

### P2 — Refresh All Metadata guard

`performRefreshInfos`
(`MyAnimeList/Sources/ViewModels/Library/LibraryProfileSettingsActions.swift`)
starts a task with no in-flight check. Several entry points can start overlapping
refreshes:

- the Mac Anime menu
- Settings
- each window

The result is doubled TMDb traffic, concurrent writes, and a shared progress toast
that jumps between runs.

**Direction:** a store-owned in-flight guard, shared by every entry point.

### P3 — Presentation and feedback ownership

Two claims can outlive the window that holds them:

- `ToastCenter.presentingSceneIdentifier`
  (`MyAnimeList/Sources/ViewModels/ToastCenter.swift`) keeps pointing at a closed
  Mac window until another window becomes active.
- The `WhatsNewController` claim
  (`MyAnimeList/Sources/ViewModels/Gadgets/WhatsNewController.swift`) can outlive
  a disconnected iPad scene.

Toast slots are global, so concurrent operations overwrite each other's
loading/progress state.

**Direction:**

- Release or hand off claims when their window closes, reusing the
  `onOtherWindowSceneClosed` hook that airing routes already use.
- Tie feedback to the operation that started it.

### General robustness (not specific to multi-window)

Recorded so they are not lost. These happen with one window too, and more windows
make them more likely.

- **Stale open detail.** An open detail view keeps copied display metadata after
  sync or a refresh changes the entry.
- **Workflows hold model objects.** Share/poster sheets and the Mac batch-delete
  confirmation keep model objects instead of re-resolving identities when
  confirmed.
- **Backup restore.** Restore replaces the store files without invalidating open
  views or async work.
- **Failed add leaves the loading toast.** `LibraryBrowseState` sets a
  non-dismissable loading toast and clears it only on success
  (`MyAnimeList/Sources/Views/Library/LibraryBrowseState.swift`). After a failed
  add, `newEntryFromSearchResults` returns `false` and the toast stays.

### Intended caveats (no change)

These follow from the maintainer's 2026-09-27 decisions to share state. They are
recorded so they are not "fixed" by accident.

- **Shared scope.** Filters, category, sort and group are shared. Revealing an
  entry in one window (Show Details, add from search, a reminder route) can reset
  the shared filters or category (`revealInInspector` in
  `MyAnimeList/Sources/Mac/MacLibraryView+Actions.swift`). That changes every
  window's contents and title, and prunes other windows' selections.
- **Shared restoration.** The last-inspected entry is a shared `@AppStorage`
  value, so restored Mac windows all select the same entry. Mac Find text is not
  restored; only inspector visibility uses `@SceneStorage`. iPad has no per-scene
  restoration.
- **UI repeated in every window:**
  - the duplicate-repair sheet (resolution itself is serialized by
    `isResolvingDuplicateEntryGroup`)
  - the reminder warning alert
  - iPad toasts
  - the iCloud conflict alert, in each iPad window with Settings open
- **Live shared edits.** Windows share entry objects, so edits appear everywhere
  at once. Undo and revert must respect who changed what (see P1).

### Open product decisions

- Should each Mac window get its own sidebar scope? Or should reveal stop
  resetting the shared filters?
- Should Mac windows restore their own selection and Find text through
  `@SceneStorage`?
- Should iPad scenes restore their own state?

## Validation and acceptance criteria

- **P1 edit ownership:** focused tests where two sessions share one entry. One
  session saves, the other discards or reverts, and the first session's saved
  fields survive.
- **P1 concurrent adds:**
  - two concurrent adds of one identity produce one row;
  - two seasons of one show added together produce one parent-series row.
- **P2 routing:** a two-window runtime pass with `make run-mac`, covering:
  - app hidden
  - only window minimized
  - target window closed
  - no library window open
  - Settings window in front

  Each case opens the entry in exactly one library window without creating extra
  windows. If App Intents that open an entry come to share this routing helper,
  the same cases apply to them.
- **P2 activation:** close every library window, re-activate the app, and confirm
  a foreground sync runs.
- **P2 Refresh All:** starting a second refresh from another entry point while one
  is running does nothing.
- **Platform split:** 008's iPad/simulator checks still need a separate pass. This
  audit did not run them.

## Refs

- Audit discussion: Claude Code session and Codex thread
  `01a14aef-0f32-7be2-87c9-7c538f55b934`, 2026-10-18.
- Baseline commit at audit time: `3665d57`.
- No code changes yet.

## Open questions

- Hidden-app extra window and minimized-only routing: both unreproduced.
- Whether reopening a window after all were closed misses any work beyond sync
  and reminder refresh.
- Codex referred to an in-progress "Open Entry" intent that shares the routing
  helper. No such source exists in the main checkout at `3665d57`, so it may live
  in another worktree.
