# 027.003 — Reject width retargeting and restore endpoint requirement

## Context

On 2026-10-17 the maintainer rejected amendment 002 after visual review. It
smooths individual 5 → 4 → 3 layouts but still hesitates at the intermediate
arrangement. During live window resizing, animation is delayed until mouse
release and produces an unacceptable reflow. The earlier automated checks
established transactions and settled states, not satisfactory live-resize motion.

## Decision before further changes

Remove the width-driven animation and its local GeometryReader, restoring the
pre-experiment Mac grid. Research first-hand reports and supported APIs before
choosing a replacement. Inspector toggles must animate directly between initial
and final card arrangements; ordinary window/divider drags must remain responsive
without queued reflow after mouse release. This replaces amendment 002's weaker
continuous-retargeting acceptance criterion.

## Research (2026-10-17)

These are related first-hand reports and documented APIs, not proof of an Apple
bug with the exact same cause as AniShelf:

- [NSHostingView in an animated NSSplitView](https://stackoverflow.com/questions/70886088/swiftui-in-nshostingview-no-animation-when-bounds-change):
  the author reports hosted SwiftUI content snapping while native sibling views
  animate. Another developer confirms encountering it; no solution is posted.
  The symptom differs from our repeated-width trace, but identifies the same
  host boundary as worth investigating.
- [Dynamic LazyVGrid resize stutter](https://developer.apple.com/forums/thread/815115):
  a February 2026 report describes resizing becoming laggy after scrolling.
  Apple's DTS engineer could not reproduce on macOS/Xcode 26.2 and requested
  environment details and a recording. This is not an acknowledged universal bug
  and the thread supplies no established workaround.
- [Inspector resize problems](https://www.reddit.com/r/SwiftUI/comments/1r35cyy/i_think_apple_needs_to_fix_swiftui_inspector_api/):
  a developer reports Mac inspector-divider crashes and unexpected width growth.
  These are adjacent symptoms, not a reproduction of our 5 → 4 → 3 hesitation.
- [Community discussion of seamless Mac grid resizing](https://www.reddit.com/r/SwiftUI/comments/olwu1z/):
  a commenter recommends NSCollectionView with a flow layout, a diffable data
  source, and SwiftUI cell content. The indexed comment was available; opening
  the full page timed out. This is a suggestion, not a verified inspector fix.
- [AppKit collection layout transitions](https://developer.apple.com/documentation/appkit/nscollectionview/collectionviewlayout):
  Apple documents assigning a destination layout through `animator()` to animate
  the layout change, with NSAnimationContext completion. This provides explicit
  endpoint control; it does not automatically suppress layout invalidations
  caused by an independently animated inspector host.
- [AppKit/SwiftUI animation integration](https://developer.apple.com/documentation/swiftui/unifying-your-app-s-animations):
  Apple documents shared animation APIs and velocity-preserving retargeting.
  Smooth retargeting still does not satisfy a requirement for one destination
  arrangement; changing the spring or using this API alone is insufficient.

## Implementation direction

**Inference from our traces and the maintainer's review:** the application must
separate the grid's destination layout from the inspector host's intermediate
presentation widths. For a toggle, compute/capture the initial and final card
frames once and interpolate between them. Do not admit a four-column layout as
an animation target when the endpoints are five and three columns. For ordinary
window/divider drags, use the current width immediately, without the toggle
animation or a deferred animation after mouse release.

The next prototype should establish how to obtain the native host's actual final
width and its transition lifecycle before changing the grid renderer. It must
cover restored inspector widths, window constraints, first presentation, and
interruption. If the SwiftUI inspector cannot provide that contract through
supported APIs, evaluate an app-owned AppKit split host and explicit collection
layout transitions. A plain NSCollectionViewFlowLayout swap is not, on its own,
a root-cause fix. No renderer/host rewrite has been selected or implemented here.

Rejected approaches:

- Another spring, linear timing, or debounce on every geometry change: retains
  intermediate targets, or introduces waiting for a guessed settling period.
- Disabling width animation only during live resizing: repairs one regression
  while retaining the rejected inspector path.
- Hard-coded 400-point subtraction: inspector width is resizable and restored,
  and host constraints may change the effective destination.
- Eager custom SwiftUI Layout without a virtualization plan: sacrifices the
  existing lazy-rendering contract while leaving host endpoint discovery open.

## Outcome and validation

The width-driven animation and its GeometryReader were removed. The source
matches the pre-experiment MacLibraryGrid exactly (`git diff --exit-code` for
that file passed). The original inspector reflow issue remains open. This is a
rollback plus research result, not a replacement fix.

The earlier checks only showed that transactions were animated and that the app
settled without crashing; they did not establish acceptable motion during a
held mouse drag. The maintainer's report supersedes that limited assessment.


`make run-mac` with the 100-entry fixture rebuilt and launched successfully after
the rollback. Accessibility inspection confirmed the Debug app displaying the
library and inspector. This is a build/launch check, not renewed acceptance of
window-resize motion. The build emitted the multiple-Mac-destinations warning.
No replacement animation implementation or new tests were added.
