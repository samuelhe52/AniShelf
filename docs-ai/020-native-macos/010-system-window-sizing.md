# 020.010 — System window sizing for the inspector

## Context

On 2026-10-16 the maintainer asked to drop the custom window-width preservation,
respect the system behavior, and prefer an AppKit setting over a home-grown
countermeasure if one exists. They also asked for a search for other code that
fights macOS defaults. (Source: this session's discussion.)

## Decision

Opening the inspector now sizes the library window the way AppKit does by
default. Two countermeasures were removed from
`MyAnimeList/Sources/Mac/LibraryView+Mac.swift`:

- `keepWindowWidthForInspector()` and its `MacUserResizeFlag` helper, recorded
  in [004](004-slice-2-mac-shell.md). It reset the window to its pre-inspector
  width after 350 ms and 900 ms delays, clamped to the visible screen.
- The sidebar auto-collapse from [008](008-mac-native-ui-pass.md)
  (`collapseSidebarIfNarrowForInspector()` and the
  `didCollapseSidebarForInspector` state in `LibraryView.swift`). It hid the
  sidebar when the window was narrower than the sidebar plus 720pt, so that AppKit
  would not widen the window.

The 720pt inspector-open column minimum was kept at first, because it prevented
the toolbar layout loop recorded in 004. The follow-up below removed it too.
Opening the inspector from a narrow window widens the window, which is the system
behavior.

## Why no AppKit setting is used

`NSSplitViewItem.collapseBehavior` controls this behavior (verified in the macOS
27 SDK header). The default for sidebars and inspectors grows the window so that
sibling panes keep their size, but never pushes the window off screen and never
grows it in full screen. `.preferResizingSiblingsWithFixedSplitView` would keep
the window's width instead. SwiftUI's `.inspector` and `NavigationSplitView` do
not expose this property. Reaching it means finding SwiftUI's private
`NSSplitViewController` in the view hierarchy. That approach was rejected as a
sturdier form of the same countermeasure.

The 004 observation that AppKit widened the window "past the screen edge"
conflicts with the header's on-screen guarantee. It was not re-measured.

## Other defaults review (not changed)

The search found these candidates. None changed in this amendment:

- The uncommitted grid-width work from the 009 follow-up measures the inspector,
  passes `macLibraryGridWidth` down, and pins the grid to a fixed frame during
  native resizes. It should be re-evaluated now that the window no longer snaps
  back after opening.
- `macSheetFrame` (`Utils/PlatformViewModifiers.swift`) makes each sheet's
  intended size its minimum, with no maximum.
- The Settings window (`MacSettingsRoot`) is resizable from 820×560, while Mac
  Settings windows are usually fixed-size panes. This is a design choice.

## Validation

`make build-mac` passed. The inspector's opening behavior in the running app was
not checked; the maintainer owns visual acceptance.

## Follow-up: removing the inspector-open column minimum (2026-10-16)

The maintainer asked to remove the 720pt minimum and test whether the layout loop
returns. The detail column now has a fixed minimum of 520pt and an ideal width of
900pt, whether or not the inspector is open (`macLibrarySplitView` in
`LibraryView+Mac.swift`). The grid-width measurement drafted for the 009 follow-up
was set aside during the test. It is not part of this change.

### Evidence

- `make build-mac` passed.
- Claude launched the Debug build with the inspector restored in a 910pt window
  (Japanese UI, sidebar hidden), then shrank the window to its minimum. AppKit
  stopped at 808pt with the inspector still open. The app kept running. Find
  expansion and relaunch at that width were not tried in this probe.
- The maintainer then tested the build and reported that the crash no longer
  reproduces. The exact conditions were not recorded.

### Why the loop may be gone (unverified)

The 004 loop needed the library column to be narrower than its toolbar, and
004's bisection found that fewer toolbar items avoided it. Since then, 006 made
the browse menu glyph-only, and 008 removed Gallery and the Search button. In
008, every minimum from 1000pt down to 680pt survived, so the smaller toolbar may
already have removed the condition. AppKit still enforces a window minimum that
leaves room for the inspector (808pt with the sidebar hidden). A fixed-width
browse menu also takes away one item whose width changed with its label, the
usual trigger for a toolbar layout loop. That contribution was not tested
separately.

Removing `keepWindowWidthForInspector()` is unlikely to be the cause, because the
crash predates it.

The cause could be confirmed by temporarily restoring Gallery and the Search
button and retesting at the minimum width. That was not done. Regression checks
for this area: with the inspector open at the minimum width, expand Find with ⌘F
and relaunch, in English and Japanese.
