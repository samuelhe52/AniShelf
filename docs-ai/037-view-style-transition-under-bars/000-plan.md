# 037 — View-style transition under the top bars: Plan

| Field | Value |
| --- | --- |
| Status | Implemented — maintainer accepted |
| Anchor date | 2026-10-31 |
| Origin | Maintainer report (2026-10-31) of a brief white-out of the top safe area during the List/Grid/Gallery switch, then of a soft-edge "blur extent" snap at the end of List → Grid. Written after the fix was implemented and accepted; it did not precede the work. |
| Related | [015-library-categories](../015-library-categories/000-plan.md) ([004](../015-library-categories/004-selection-highlight-without-matched-geometry.md) covers a separate pop-in bug in the same transition) |

## Background

`LibraryEntryPage` gives each layout page its own identity and attaches
`LibraryViewTransitions.libraryViewTransition()`: an asymmetric modifier transition
that scales, rises, blurs, and fades the incoming page in and the outgoing page out.
The pages are scroll views (`List` for List, `ScrollView { LazyVGrid }` for Grid)
whose content extends under the navigation bar and the optional category strip, where
the bar's soft scroll-edge effect (`preferredNavigationBarScrollEdgeEffect()`) blurs it.

Two artifacts showed up when the page was scrolled so content sat under the bars:

1. **White-out.** During the switch, the band under the bars went plain white. The
   rows under the bars reappeared only after the animation settled.
2. **Soft-edge snap.** After the white-out fix, List → Grid showed the soft-edge blur
   over that band weaker while the transition ran, then jumping to full strength in
   one frame when it finished. Grid → List did not.

## Goals

- Keep content under the bars drawn, with its normal soft-edge treatment, throughout
  the switch, in both directions.
- Keep the transition's look: endpoints (scale, rise, blur, opacity) and timing
  (`libraryViewStyleAnimation()`) unchanged.

### Non-goals

- The intermittent pop-in (incoming page appears with no transition) tracked in
  [015.004](../015-library-categories/004-selection-highlight-without-matched-geometry.md).

## Design / approach

In `MyAnimeList/Sources/Views/Library/LibraryViewTransitions.swift`,
`LibraryViewTransitionModifier` renders in this order:

1. `LibraryPageGeometryEffect(scale:yOffset:).ignoredByLayout()` — a custom
   `GeometryEffect` that scales about the center and then shifts, replacing
   `.scaleEffect` + `.offset`.
2. `.compositingGroup()`.
3. `.visualEffect { blur + opacity }`. The modifier is `Animatable` over blur radius
   and opacity so the closure receives interpolated values; scale and offset
   interpolate inside the geometry effect.

## Alternatives & decisions

Each row was measured on the simulator from recordings (see 001).

| Choice | Reason and alternative |
| --- | --- |
| Geometry through a `GeometryEffect` with `.ignoredByLayout()` | Any non-identity `.scaleEffect` or `.offset` on the page hid the under-bar content until the animation settled (each tested alone with opacity). Opacity alone and no custom transition kept it. Removing the motion was the fallback; `.ignoredByLayout()` kept it. Suggested by a Codex web search citing Apple's `ignoredByLayout()` docs ("disable layout changes during transitions"). |
| Group before `visualEffect`, blur/opacity inside it | With blur/opacity applied directly to the page, the soft edge changed strength when List → Grid finished. Removing blur, then also the group, did not remove the snap. An opaque incoming page with only the outgoing page fading also still snapped (617 → 588), so incoming opacity below 1 is not a sufficient explanation. |
| Keep `.compositingGroup()` | Without it, an incoming page with `.blur` showed no blur or fade and appeared sharp. |
| Rejected: drop scale/offset entirely | Avoided the white-out but lost the rise/zoom; the geometry effect made it unnecessary. |
| Rejected: `.visualEffect` for scale/offset (first attempt) | Its runs popped in, but those were taken right after scrolling with the strip shown, where the 015.004 pop-in also hits the committed code, so the result was confounded rather than a measured failure. |

## Validation and acceptance criteria

- Grid scrolled so content sits under the bars, category strip disabled (to exclude
  the 015.004 pop-in); record List → Grid and Grid → List and check frame by frame
  that the incoming page blurs in (sharp pop-ins are invalid runs, not passes).
- No white excursion in the top band; no one-frame drop in edge energy under the
  title at transition end.
- Maintainer visual check on the simulator.
- `make build-mac`.

## Amendments

None yet.
