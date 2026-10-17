# 025.002 — Status picker initial alignment

## Context

On 2026-10-18 the maintainer supplied two screenshots: the whole Mac segmented
picker initially protrudes beyond the tracking card's trailing content edge,
then aligns after interaction. Reproduced in the running Japanese-language app
without changing any stored status. Changing horizontal `fixedSize` did not
resolve it. A subsequent `geometryGroup` experiment aligned on launch but failed
again after switching entries.

The evidence points to the SwiftUI segmented picker's native layout boundary;
the precise framework-internal cause is not established.

## Plan

Replace only the Mac status picker with a small `NSViewRepresentable` around
`NSSegmentedControl`, explicitly reporting its fitting size. Preserve the existing
binding and status-change callback, disabled state, localized rewatch label, and
native keyboard/accessibility behavior. Refresh the coordinator's binding on each
update so reused controls cannot edit a previously selected entry. Keep iOS on
the existing SwiftUI picker.

Reject delayed redraws, arbitrary offsets, and identity resets on selection:
they mask the layout issue or discard control focus. Discard both failed modifier
experiments. Validate with a Mac build and live initial display, entry switching,
and inspector reopening; do not mutate real library status for UI validation.

## Current state

Implemented in `MyAnimeList/Sources/Mac/MacWatchStatusPicker.swift`, routed from
`MyAnimeList/Sources/Views/Library/AnimeEntryTrackingControls.swift`. Existing
localized resources are resolved with the SwiftUI locale; no new copy was added.

## Validation

- `make run-mac` built and launched the replacement. Initial compilation emitted
  coordinator actor-isolation warnings; the coordinator is now explicitly
  `@MainActor`.
- Live Japanese-language UI observations: aligned trailing edge on launch, after
  switching from a Watching entry to a Planned entry, and after hiding/reopening
  the inspector. The earlier geometry-group experiment failed the entry-switch
  check in the same running-app workflow. Screenshots were inspected locally,
  not retained as repository artifacts.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/MacWatchStatusPickerTests'`:
  two Swift Testing tests passed. They cover deferred selection and replacement
  of the coordinator's binding. The first attempt failed because the new test
  file lacked the project's explicit test-target membership exceptions; these
  were added to `MyAnimeList.xcodeproj/project.pbxproj` before the passing run.
- Targeted Swift formatting lint and `git diff --check` passed.

The exact SwiftUI framework defect remains inferred. Live status mutations,
keyboard navigation, other locales, and narrow inspector widths were not manually
tested; final visual acceptance remains with the maintainer. iOS retains its
existing picker implementation and was not built in this follow-up.
