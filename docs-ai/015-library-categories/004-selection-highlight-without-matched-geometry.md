# 015.004 — Selection highlight without matched geometry

## Context

On 2026-10-30 the maintainer reported that switching the library view style
(List, Grid, Gallery) animated wrongly while the category strip was visible. In
the normal transition, the outgoing page blurs out as the incoming page blurs in
(`LibraryViewTransitions.libraryViewTransition()`). With the strip showing,
grid→list put the list on screen sharp and immediately, over the fading grid, and
list→grid had no transition at all. The maintainer also observed that turning the
strip off fixed the animation only after a relaunch.

## Diagnosis

Reproduced on the booted iPhone 18 Pro simulator by recording each switch and
reading the frames. The bug is intermittent, so the final comparisons used
several switches per launch.

| Variant | Result |
| --- | --- |
| Original code | Broken; 2 of 2 checked switches in one session |
| Strip replaced by a plain colored view in the same `safeAreaInset` | Correct, so the inset is not the cause |
| Strip without `matchedGeometryEffect` (glass kept) | Correct on 4 of 4 switches in one session; one earlier single run right after a fresh install was broken |
| Final fix | Correct on 4 of 4 switches (none made right after scrolling; see Current state) |

Earlier single-run bisect steps (`safeAreaBar`, an overlay with `safeAreaPadding`,
removing `glassEffect`) were inconclusive because of the intermittency and are not
evidence either way.

The cause is the strip's selected-tab capsule, which used
`matchedGeometryEffect(id: "selection", in:)`. While it is on screen, the
view-style switch loses its page transitions. Why matched geometry in a sibling
hierarchy affects those transitions is unknown.

## Change

The per-tab matched-geometry capsule was replaced by one capsule in the tab row's
background. It is sized and offset from the tab widths the strip already measures
for drag reordering. The highlight still slides with the strip's `.snappy`
category animation. While the selected tab is being dragged, the highlight follows
`draggedCenter` and drops animation, matching the held tab. It stays hidden until
the selected tab has been measured. `tabCenter` and the highlight now share a
`tabMinX` helper.

Rejected: moving the strip out of `safeAreaInset`. The plain-view test showed the
inset is not involved.

## Refs

- `MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryStrip.swift`
- Validation (2026-10-30, simulator): 4 alternating List/Grid switches all
  crossfaded with blur; tapping a category slid the highlight onto the new tab;
  in reorder mode the highlight tracked a dragged selected tab and settled in its
  new slot (order restored afterwards). `make build-mac` passed.
- Committed with this amendment in `3dc7e1a3`.

## Current state (corrected 2026-10-31)

The `3dc7e1a3` fix was incomplete. The remaining glass/animation interaction is now
addressed by [005](005-page-insertion-after-scrolling.md), validated on `59c6ad64`
with that fix applied. The historical reproduction remains valid: with
`3dc7e1a3` and the strip shown, switching Grid → List right after scrolling the grid
made the list pop in with no transition on 4 of 4 switches (simulator, 2026-10-31).
The 2026-10-30 validation had no scroll before its switches. The maintainer isolated
it by disabling the strip. However, one experimental transition variant still popped
in once with the strip disabled (037's Codex runs), so the strip may not be the only
factor. Removing the matched-geometry highlight did not remove every trigger. 005
traced the remaining one to the strip's glass taking part in the view-style animation;
SwiftUI's underlying cause is still unknown. The under-bar white-out and soft-edge
snap found during that session are a separate issue, recorded in
[037-view-style-transition-under-bars](../037-view-style-transition-under-bars/000-plan.md).

## Open questions

- Why `matchedGeometryEffect` in the strip suppresses unrelated insertion and
  removal transitions.
- The relaunch-only recovery after turning the strip off was reported, not
  reproduced. A guess, not tested: matched-geometry state outlives the strip.
- Other `matchedGeometryEffect` uses (for example
  `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`) were not
  checked for the same interaction.
