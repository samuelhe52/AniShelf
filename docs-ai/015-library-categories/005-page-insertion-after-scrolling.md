# 015.005 — Isolate the strip from page-style animations

## Context

Follow-up to 004 on 2026-10-31, starting at `59c6ad64`. With the category strip
visible, incoming List/Grid pages sometimes appeared sharp and opaque while the
outgoing page faded. 037's under-bar geometry and soft-edge fixes had to remain
intact. Research and a three-scenario baseline preceded implementation; temporary
probes and rendering variants were removed before final validation.

## Diagnosis

**Confirmed in the sampled runs:** the incoming transition lost interpolation,
not just the appearance of its blur/opacity. In two visibly bad Grid → List
switches, the transition modifier's incoming values went from opacity 0 / blur 8
to opacity 1 / blur 0 within about 5–6 ms, with no interpolated setter samples.
The outgoing modifier still produced 43 and 29 samples. Two clean List → Grid
switches produced 43 and 44 incoming samples. Strip scroll-geometry and viewport
callbacks reported no changes around those bad switches.

Keeping the strip's state/scroll code but replacing only its glass with a solid
background gave six visually clean switches. Moving the glass to a separate
background did not fix it (five of six probed insertions still skipped).
`GlassEffectContainer` gave four clean probed switches, but a sharp List insertion
returned in the probe-free repeats; that candidate was rejected.

**Inference:** the strip's Liquid Glass participating in the page-style animation
interacts with SwiftUI's insertion/transaction handling. This investigation does
not establish the internal UIKit/SwiftUI cause. It found no evidence for a
scroll-geometry callback colliding with the switch in the probed cases, and did
not need to change page scroll restoration. Removing glass was diagnostic, not
an acceptable final design.

## Change

`LibraryCategoryStrip` adds `.animation(nil, value: scope.viewStyle)` after its
existing category-selection and reorder animation modifiers. This keeps the
page-style update's animation out of the strip subtree. Category selection and
reorder animations still have their own triggers. The capsule's native glass,
layout, scroll bindings, geometry callbacks, and gestures are unchanged.

`LibraryViewTransitions.swift`, `LibraryEntryPage.swift`, and `LibraryView.swift`
are unchanged from `59c6ad64`. In particular, 037's ignored-by-layout geometry
effect and grouped visual-effect blur/opacity remain intact. No delayed state
changes, snapshots, new transition phases, or permanent probes were added. The
maintainer confirmed the fix on the simulator on 2026-10-31.

## Validation

Only the already-booted iPhone 18 Pro simulator
`A06216D2-8EA3-4101-9BC5-9F45356CCA35`, with iOS 27.2, was used. Settings showed the
strip already enabled at the start. Each scenario used three alternating pairs;
pass means the incoming page visibly blurred in, moved, and faded. The final
18 switches were probe-free and spanned two app launches.

| Scenario | Before List → Grid | Before Grid → List | After List → Grid | After Grid → List |
| --- | --- | --- | --- | --- |
| No preceding scroll | 1/3 | 0/3 | 3/3 | 3/3 |
| Scroll, then switch through the style menu | 0/2 assessed | 0/3 | 3/3 | 3/3 |
| Scroll, wait five seconds, then switch | 0/3 | 0/3 | 3/3 | 3/3 |

One baseline immediate List → Grid recording had a multi-second capture gap and
was excluded. Some other baseline recordings had shorter gaps; their observed
sharp incoming content remained visible under the still-fading outgoing page.
Counts describe inspected recordings, not a population failure probability.

Additional checks:

- Three measured, valid final pairs retained under-bar content with no white band
  and no sustained terminal soft-edge snap. In late-settle windows, the largest
  adjacent energy falls were 3/3/3 for Grid insertions and 2/2/3 for List
  insertions (same grayscale edge-energy ×100 metric as 037). Absolute values
  differed with the posters under the title; these are image metrics, not native
  blur measurements. Top-band brightness changed toward the settled content value
  without a transient white excursion followed by an end-of-transition drop.
- Category taps selected both existing categories and restored All. A short held
  drag in reorder mode moved the selected highlight; the category order stayed
  All / 百合 / 音乐. Reordering was exited afterwards.
- `make run-sim`, `make build-mac`, and `git diff --check` passed. Formatting was
  limited to the changed Swift file. No automated tests were added for this visual
  rendering/transaction regression.
- Final state: strip enabled, All selected, List shown, reorder mode off.
- Recordings, per-frame contact sheets, and probe logs were local debugging
  artifacts, not retained in the repository.

## Search sources and limits

No public report found matched this exact category-strip/page-insertion failure.

- Apple documents [animation(_:value:)](https://developer.apple.com/documentation/swiftui/view/animation(_:value:))
  as applying animation when the monitored value changes, with `nil` disabling it.
  [Transaction](https://developer.apple.com/documentation/swiftui/transaction)
  carries the animation through the hierarchy. These document the scoping tool,
  not this glass bug or its workaround.
- Chris Eidhof's first-hand [Transactions and Animations](https://www.objc.io/blog/2021/11/25/transactions-and-animations/)
  explains subtree transaction overrides and diagnostic transaction printing.
- A separate first-hand [glass/navigation transition report, FB19016414](https://swiftui-garden.com/Misc/iOS-26/View-Stuck-in-background-during-transitions-in-a-nav-stack-with-glass-backgrounds)
  describes a view stalling during mixed glass/opaque navigation transitions.
  Its hierarchy and workaround differ; it is related context, not confirmation
  that AniShelf has the same underlying defect.

## Remaining limits

Only this simulator/runtime and a small library configuration were exercised.
Physical devices, iOS 26 runtimes, Gallery transitions, and a strip wide enough to
require horizontal overflow were not validated. The short drag did not change
category order, so a full reorder permutation was not rerun. SwiftUI's internal
reason for the glass/animation coupling remains unknown.
