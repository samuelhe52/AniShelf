# 031.004 — Slice 2: Hybrid library toolbar for vertical bars

## Context

Slice 1 was accepted in the review appended to `003-native-host-migration.md`.
This slice starts at `76f6012` and implements the plan's toolbar step. The
maintainer's constraint is **"don't make other devices' appearance change."**
When `toolbarVerticalEdge == nil`, the toolbar must render as it does at `76f6012`.
Library toolbar behavior while an inspector is open belongs to slice 3. The
detail sheet's Done belongs to P3.

Codex implemented the first version, which put every item in the vertical bar.
The maintainer rejected it after a visual pass (see "Rejected: all-vertical
toolbar" below). Claude Code then researched Apple's guidance and reworked the
slice into the hybrid described here, with the maintainer's approval
(2026-10-22). The rework was amended into the same commit.

## Apple guidance (source documents)

From [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo),
[Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo),
and the tech talk [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/):

- The system merges navigation bars, toolbars, and tab bars into one vertical bar.
  Top-bar and bottom-bar items keep their groups, with "a vertical spacer visually
  separating top and bottom placements even when unified into a single bar."
- An item goes vertical only if it has a symbol. Text-only items and custom views
  stay horizontal. The talk: "if the text does contain meaningful information …
  it's better to keep the control in the horizontal bar." Horizontal and vertical
  bars can be on screen together. `axisBehavior(.horizontalOnly)` /
  `.verticalPreferred` override the default. The talk's example of a horizontal-only
  item is a custom Select/Done button.
- Keep controls' relative positions consistent across poses. Reserve the top of
  the vertical axis for Close/Back, then prominent actions. Use the system overflow
  menu, and keep the ellipsis symbol for it alone.
- Items can move to the vertical bar only when their container sits along the
  display edge. Inspectors never get a vertical bar. Slice 3 depends on this.

## Change

On iOS 27.1+, with `toolbarVerticalEdge != nil` and no inspector presented:

- **The header stays horizontal and unchanged.** The vertical branch reuses
  `topBarContent` as it is: the count/category title capsule, the title spacer,
  the "Select" text button, the composite profile icon, and, in selection mode,
  the selected count. These items are text or custom views, so the system keeps
  them in a horizontal top bar.
- **Bottom controls become symbols in the vertical bar** at `.bottomBar`, so they
  form the lower group:
  - Browsing: a view-style `Menu` with a titled-symbol label (a top-level `Picker`
    stays horizontal), the sort/group/filter menu as an icon whose glyph fills
    while filters are active (`LibraryBrowseSummaryMenu(usesSymbolLabel:)`), and
    Search.
  - Selection: delete, status, favorite, and category. The date and score actions
    move to `ToolbarOverflowMenu`. In the horizontal toolbar they stay in the
    existing ellipsis "Actions" menu, which now shares their content through
    `LibrarySelectionActionsMenu.actions`.
- Search has a high visibility priority. View style and delete have a low one.
- In every other context the toolbar is the unchanged `topBarContent` +
  `bottomBarContent`.
- No string-catalog changes. The vertical-only count menu and its badge from the
  first version are gone, so `%lld Anime` and `Selected` are unused again on iOS
  and keep their original stale state.

### Rejected: all-vertical toolbar (first version, `e95e62f`/`25d4505`)

All six items went into `.primaryAction`. The count became an icon with a native
badge, and Select and profile became symbols. The maintainer rejected it after a
visual pass:

- It was one undifferentiated column. Top-bar and bottom-bar placements lost their
  grouping and their relative positions, which goes against Apple's consistency
  guidance.
- The library count turned into a red badge reading like an unread count. The count
  item's `books.vertical` icon sat next to the profile button's
  `books.vertical.fill`.
- A follow-up that hand-built a gray badge in a `ZStack` label was interrupted and
  discarded. Apple says custom views don't join the vertical bar.

The research supported a hybrid. Apple keeps meaningful text horizontal (its own
Select/Done example) and lets horizontal and vertical bars coexist.

### Isolation findings (first version, runtime evidence)

Codex probed the cover display (466×678 pt) with temporary launch-argument toolbars,
removed before commit:

| Probe | Observation |
| --- | --- |
| Remove the title, summary capsule, Select, clear spacer, or profile one at a time | The remaining bars stay horizontal; no single item explains it. |
| Remove all five, leaving View Style and Search | Both stay horizontal in the bottom bar. |
| Native Search alone at `.primaryAction` | Joins the vertical column. |
| Native Search alone at `.bottomBar`, automatic and `.verticalPreferred` | Stayed horizontal. |
| Top-level Picker with a titled symbol | Stays horizontal; a labeled `Menu` holding the same picker goes vertical. |

The `.bottomBar` result is **contradicted by the hybrid**. With the original
horizontal top bar present, native `.bottomBar` items do go vertical on the cover
and in inner landscape. The cause of the earlier probe result is unknown. It was
not reinvestigated because the hybrid does not depend on it.

## Refs

- `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`
- `MyAnimeList/Sources/Views/Library/LibraryBrowseSummaryMenu.swift`
- Baseline: `76f6012`.

## Validation

Hybrid validation (Claude Code, 2026-10-22), on the already-booted iPhone Duo
simulator (iOS 27.1) only, after `make run-sim`:

- Cover (466×678 pt), browse: the header capsule ("135 アニメ"), Select, and the
  gear profile icon stay horizontal at the top. View style, filter, and Search form
  a separate group at the bottom of the vertical bar (x=399, y 507–611). Checked
  with a sim-use outline and a Device Hub window capture, because sim-use cover
  screenshots are black.
- Cover, selection: the "1 アニメ" header stays horizontal. Close and the system
  overflow sit at the top of the vertical bar. Delete, status, favorite, and
  category form the bottom group.
- Inner landscape (951×669 pt): browse looks the same as on the cover. In
  selection, the overflow menu opened with Track Dates, Hide Dates, and Score. No
  action was applied.
- Inner portrait (669×951 pt): browse and selection outlines match the original
  horizontal toolbar. That includes the view-style Picker, the "すべて" capsule,
  and the "Actions" ellipsis menu with its disabled state.
- Targeted `swift format lint` on both changed Swift files passed. The string
  catalog equals `28ae91a`.

Unverified: non-Duo devices at runtime (no other simulator was booted; the
horizontal branch is source-identical to `76f6012`), named categories or
reordering in the vertical form, applying batch actions, and the gallery and grid
styles in the vertical form. The first version's focused interaction and session
tests passed, but this slice doesn't touch that code.

## Current state

Slice 2 implemented as the hybrid. Slice 3 (library controls while the inspector
is open) and P3 have not started. No push was made.
