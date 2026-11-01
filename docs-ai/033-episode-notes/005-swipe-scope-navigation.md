# 033.005 — Swipe between note scopes

## Context

On 2026-10-27, the maintainer requested left/right swipes inside the inline note
content to switch scopes. After initially confirming the interaction worked, the
maintainer reported intermittent capsule skipping when starting a swipe in All.
This amendment records the initial implementation and its follow-up correction.

## Change

- On iOS, left advances and right goes back through All, Overall, and episode
  chips in their displayed descending season/episode order. Include the selected
  empty episode draft; exclude the separate suggested-note and Other… controls.
  Stop at either end instead of wrapping.
- `PlaceholderTextEditor` accepts an optional horizontal-swipe callback. Its
  UIKit editor uses discrete left/right swipe recognizers, permits simultaneous
  recognition with its scrolling pan, and declines scope swipes while text is
  selected or an IME marked-text range exists. Other editor callers omit the
  callback. Native macOS editor gestures are unchanged.
- The initial All implementation used a `simultaneousGesture` drag. Its note rows also have button actions. Source inspection after
  the skipping report identified competing row selection and swipe navigation as
  a plausible cause: a row could change the selection before the swipe handler
  calculated its next scope. The event ordering was not independently reproduced
  or captured in a trace; this explanation remains an inference.
- Replace All's simultaneous drag with `EntryNotesOverviewSwipe`, a
  `UIGestureRecognizerRepresentable` using discrete directional swipes. Recognized
  swipes cancel row touches and delay touch-end delivery; simultaneous recognition
  is allowed only with a scroll view's scrolling pan. Left from All directly
  targets Overall. Right from All consumes the swipe without selecting a row,
  because All is the first scope. This avoids deriving All's destination from a
  potentially changed selection while preserving vertical scrolling by design.

## Refs and current state

- Swipe navigation, the All gesture correction, and this amendment are included
  in the same commit as the [All return button](006-return-to-all.md).
- Sources: `MyAnimeList/Sources/Views/Gadgets/PlaceholderTextEditor.swift` and
  `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`.

## Validation

| Check | Result |
| --- | --- |
| Initial implementation | `make run-sim` (fixture library) and `make build-mac` passed. |
| Initial interaction checks | Agent observed All-to-Overall swiping and suggested-note selection. The maintainer initially confirmed the feature worked, then reported intermittent skipping specifically in All. These checks do not establish complete gesture correctness. |
| All gesture correction | `make build` and `make build-mac` passed. |
| Runtime acceptance of the correction | Not checked. The maintainer requested no further visual checks; no additional simulator interaction, physical-device run, or automated test was performed for the correction. Row taps, vertical scrolling, boundary swipes, and absence of skipping still need runtime acceptance. |
