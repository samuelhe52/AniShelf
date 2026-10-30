# 037 — View-style transition under the top bars: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-31 | Bisected the white-out: scale and offset each cause it; opacity, blur, and the compositing group do not. | Simulator recordings |
| 2026-10-31 | Replaced `.scaleEffect` + `.offset` with `LibraryPageGeometryEffect` + `.ignoredByLayout()`; maintainer confirmed Grid → List and reported the List → Grid soft-edge snap. | Uncommitted |
| 2026-10-31 | Bisected the snap (blur, group, and incoming opacity each ruled out as sole cause); Codex moved blur/opacity into `.visualEffect` after `.compositingGroup()`, then simplified the `Animatable` data to blur and opacity only. Maintainer accepted. | Uncommitted |

## Outcome and current state (as of 2026-10-31)

`LibraryViewTransitionModifier` applies `LibraryPageGeometryEffect(...).ignoredByLayout()`,
then `.compositingGroup()`, then `.visualEffect { blur, opacity }`, and is `Animatable`
over blur radius and opacity. Transition endpoints and `libraryViewStyleAnimation()`
are unchanged. `LibraryEntryPage.swift` and `LibraryView.swift` are unchanged.

- `MyAnimeList/Sources/Views/Library/LibraryViewTransitions.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryPage.swift` (attaches the transition)
- `MyAnimeList/Sources/Extensions/SwiftUI+Helpers.swift` (`preferredNavigationBarScrollEdgeEffect()`)

## Deviations from plan

None known. The plan was written after the fix (see its Origin).

## Validation

All on the booted iPhone 18 Pro simulator (iOS 27.2 runtime), with the grid scrolled
so content sat under the bars. Measurements come from screen recordings: top-band
brightness for the white-out, and edge energy of a band under the title for the
snap. These are image metrics, not native blur values.

- White-out, original code: top band rose to about 196 (white) mid-transition and
  fell back when the animation settled. Same with scale-only and offset-only variants;
  absent with opacity-only.
- Snap, `GeometryEffect` baseline: one-frame drops of 639 → 587 (maintainer's
  recording), 616 → 586, 620 → 583, and 617 → 587 (geometry + opacity only).
- Final variant (Codex's runs, from its report): two List → Grid insertions settled at
  584–585 and 581–587, with no sustained terminal drop (one transient 586 → 581 → 586);
  two Grid → List insertions settled at about 555–561 with no terminal snap. All four
  visibly blurred in. Top band moved gradually between about 172 and 180, with no
  white excursion.
- `make run-sim` and `make build-mac` passed (Codex). No automated tests: the
  regression is visual.
- Maintainer visual check on the simulator: accepted.

## Open questions

- The mechanisms are unconfirmed: why transforms on the page hide the under-bar content,
  and why blur/opacity applied directly to the scroll view weakens the soft edge until
  the transition ends. No public report matched either symptom.
- Only checked on the iOS 27.2 simulator, not on a device or an iOS 26 runtime.
- A small transient fluctuation (about 5–8 energy points, recovering within about
  67 ms) remained in some List → Grid runs.
- Gallery was not measured.
