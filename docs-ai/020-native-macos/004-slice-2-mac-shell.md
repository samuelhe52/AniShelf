# 020.004 — Slice 2: Mac shell

## Context

Second slice of [002-implementation-decisions.md](002-implementation-decisions.md).
Partway through slice 1 the maintainer changed the roles: Claude Code became the
primary implementer, and one Codex session (GPT-6.1 Sol, high effort, Fast tier)
drives the built app with computer use, returns screenshots, and reviews code.
Every round below ran against a copied snapshot build outside the source tree,
so inspection never raced source edits.

## Change

### Window

- `LibraryView` hosts a `NavigationSplitView` on the Mac. The sidebar
  (`MyAnimeList/Sources/Mac/MacLibrarySidebar.swift`) lists All Anime, the four
  watch statuses, Favorites/TV Series/Movies, and the categories with counts.
  `LibraryStore.macLibraryScope` maps a sidebar row onto the existing shared
  `filters` and `activeCategoryID`, as 002 decided. Categories can be renamed,
  deleted, created, and reordered from the sidebar.
- The iOS category strip is never shown on the Mac.
- The window title is the scope; the subtitle is the visible count or
  "N Selected".
- The toolbar (`LibraryToolbar.macContent`) holds the view-style segmented
  control, the existing sort/group/filter menu, Add Anime, Search, and an
  inspector toggle. During a batch selection it shows the batch actions instead.

### Selection

- Grid: a click inspects one entry. ⌘-click toggles and ⇧-click extends a batch
  selection; the modifiers are read from the click event itself. Selected cards
  get an accent ring instead of the iOS dimming.
- List: native `List` selection drives the same state machine
  (`LibraryView+Desktop.swift`, `applyMacSelection`). Arrow keys move the
  inspected entry. The row's inert tap overlay is omitted on the Mac because it
  stole clicks and focus from the table. iOS keeps the overlay; see
  [014](../014-multiselect-invariants/000-plan.md).
- A batch selection still uses the iOS multi-select snapshot through
  `enterMultiSelection()`.

### Inspector

Entry detail stays in the trailing inspector. On the Mac the inspector is
attached to the library column inside the split view
(`LibraryEntryInspectorModifier`). The column's minimum width is 520pt, or 1000pt
while the inspector is open, and its ideal width stays constant. (The
inspector-open minimum was removed in [010](010-system-window-sizing.md); the
loop did not reproduce with the smaller toolbar.)

Two failures led to this layout. Both were measured, not inferred:

- With the inspector attached outside the split view, AppKit counted the
  inspector's width twice in the window's minimum (1550pt on a 1512pt display).
  A temporary `NSWindow.minSize` log, run with column-width variations,
  confirmed this.
- When the library column became narrower than its toolbar, opening the
  inspector put AppKit into an endless layout loop: 300 layout passes, then
  `NSGenericException`. The crash reproduced at launch with a restored
  inspector. Launch-flag bisection showed that only "fewer toolbar items" or "a
  narrower inspector" avoided it, so the fix guarantees the column width rather
  than removing toolbar items. A changing ideal width was rejected because it
  resized the window on every inspector open.
- Even with the column inside the split view, AppKit widened the window when
  the inspector opened near the minimum width, by up to 590pt and past the
  screen edge. A temporary headless harness toggled the inspector and logged
  window frames to confirm this. The library side needs about 600pt next to the
  inspector before AppKit stops widening, which is where the 1000pt
  inspector-open minimum comes from. (Superseded: [008](008-mac-native-ui-pass.md) lowered it
  to 720pt once the toolbar lost Gallery and the Search button.)
  `keepWindowWidthForInspector()` then restored the user's width, grew it only
  to the new minimum, and clamped it to the visible screen. (Removed in
  [010](010-system-window-sizing.md); AppKit's default sizing now applies.)

### Commands, Settings, sheets

- `MacLibraryCommands` (`MyAnimeList/Sources/Mac/MacLibraryCommands.swift`)
  defines these menu-bar commands:
  - File: Add Anime… ⌘N, New Window ⌥⌘N.
  - Edit: Find in Library… ⌘F, Select All Anime ⇧⌘A.
  - View: Gallery/List/Grid ⌘1–3, inspector ⌥⌘I, plus sidebar commands.
  - Anime menu: Show Details, Edit, favorite, Switch Poster, Share, Delete, Edit
    Categories, Refresh All Metadata.

  The key window publishes its actions through `focusedSceneValue`. Search opens
  in TMDb mode for Add and in Library mode for Find, through a new optional
  `SearchPage` initial mode.
- The Settings scene (⌘,) hosts `LibraryProfileSettingsView`, which on the Mac
  becomes a System Settings–style split view: Overview (the library statistics
  and App Info) plus the six settings pages. This replaces the planned tabbed
  window; the settings pages already exist as sections, so the sidebar reuses
  them unchanged.
- Settings text and controls that only apply to iOS are hidden on the Mac:
  single-tap detail, soft navigation bar edges, the sticky category strip, and
  the iPhone category instructions. Custom-labeled menus no longer show a
  second chevron. What's New opened from Settings presents in the Settings
  window.
- Mac sheets use `macSheetFrame(width:height:)`, because macOS sizes a sheet to
  its content's ideal size, which collapses lists. They also get a text Close
  button (`SheetCloseLabel`). The gallery gets hover arrows and ←/→ paging,
  because a mouse wheel cannot scroll it sideways.

### Early slice-3 work in this slice

Mac lifecycle (`MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift`):

- Periodic airing-reminder refresh with `NSBackgroundActivityScheduler`.
- Notification presentation and click routing.
- `applicationShouldTerminate` waits up to 10 s to flush pending local sync.
- Pending edits are pushed before sleep, and a sync runs after wake.
- An activity assertion (with sudden termination disabled) covers in-flight sync.

Slice 3 still has to validate these at runtime.

### Fixes from review

- Mac window identity uses object identity (`NSWindow.sceneIdentifier`), not
  `windowNumber`, which is `-1` before a window has a device (Sol's slice-1
  review).
- From Sol's slice-2 review:
  - Quitting replies to AppKit exactly once, from either the flush or the
    10-second timeout (`TerminationReply`). The pending-sync wait ignores
    cancellation, so the timeout no longer awaits it.
  - Sleep and wake are observed once at application lifetime
    (`LibrarySyncNotificationBridge.configureSleepAndWake`), not per window. The
    handlers capture the store and the recovery gate rather than the App value,
    whose `@State` would be stale after startup recovery.
  - ⌘-clicking the only selected entry clears it.
  - Show Inspector during a batch selection narrows the batch to one entry.

## Validation

- Builds: `make build-mac` and `make build` pass.
- iOS tests: `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests MyAnimeListTests/LibraryProfileSettingsStateTests MyAnimeListTests/LibrarySyncNotificationBridgeTests MyAnimeListTests/AppLifecycleEventGateTests MyAnimeListTests/AnimeSharingTests MyAnimeListTests/LibraryGalleryLayoutPolicyTests'`
  passed on the already booted iPhone 18 Pro simulator.
- Computer-use rounds `s2a`–`s2g` (screenshots and reports were local and not
  retained):
  - Sidebar scopes and two-window scope sync.
  - Grid and List selection, including ⌘ and ⇧ clicks and arrow keys.
  - Inspector open/close at minimum and wide widths, without crashing.
  - Menus, Add/Find sheets, Settings pages, sharing, poster picker, category
    manager, light and dark appearance.
- The layout-loop crash was reproduced headlessly by launching with a restored
  inspector and checking whether the process survived. After the fix it no
  longer reproduced at 840–1550pt widths.
- Not covered by automation: real pointer hover on the gallery arrows, and
  opening menu-bar menus. Menu items were verified from the menu contents.

## Refs

- New files:
  - `MyAnimeList/Sources/Mac/MacLibrarySidebar.swift`
  - `MyAnimeList/Sources/Mac/MacLibraryCommands.swift`
  - `MyAnimeList/Sources/Mac/MacSettingsRoot.swift`
  - `MyAnimeList/Sources/Views/Library/LibraryView+Desktop.swift`
- Main changes:
  - `MyAnimeList/Sources/Views/Library/LibraryView.swift`
  - `LibraryToolbar.swift`, `LibraryGridView.swift`, `LibraryListView.swift`, `LibraryGalleryView.swift`
  - `LibraryProfileSettingsView.swift`
  - `MyAnimeList/Sources/App/MyAnimeListApp.swift`
