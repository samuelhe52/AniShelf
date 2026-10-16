# 020.009 — Inspector and settings follow-up

## Context

The maintainer's 2026-10-16 visual pass disproved the completion claims in 008:
Mac grid opening still jitters, batch selection does not open the inspector, and
poster removal/order transitions are incorrect. iPad animates correctly even in
the middle of the library; the previous scroll-position explanation was unsupported.

## Plan

Restore the grid-local animation approach verified in Git commit `f2ef101` (scoped
transaction and geometry grouping), removing the Mac's delayed scroll correction.
Separate inspector presentation state from replacement of its content. Keep poster
identity and selection order stable, animate the displayed collection itself, and
use a consistent fan direction so existing posters do not alternate sides.

Expose Appearance sections directly to Form. Replace imitation popup chrome and
nested single-choice menus with native Picker controls; preserve multi-choice
filter semantics. Bound sidebar symbols to a common inset. The replacement Image #1 identifies Sync Now; its shared helper now uses a native
Mac push button, including the related deleted-cloud-library actions.

## Validation

Planned: native Mac build, focused interaction tests, iOS compilation if an already
booted simulator is available. Maintainer owns visual acceptance. No build or unit
test establishes animation quality or native inspector opening behavior.

## Implemented source

- Mac inspector uses a stored presentation binding, reconciled with detail/batch
  visibility, rather than a computed binding that changes meaning during content
  replacement. Starting a batch resets its hidden flag.
- Grid uses the iPad-scoped smooth transaction, including batch visibility. Removed
  per-card geometry collection, timed anchor retention, and corrective scrolls.
  Existing AppKit window-width preservation remained at the time; its contribution to
  any residual jitter needed visual verification. (Removed in
  [010](010-system-window-sizing.md).)
- Poster membership updates atomically with selection order in an animated
  transaction. Older posters fan in one direction instead of alternating sides.
- Appearance sections are direct Form sections on Mac; iOS retains its VStack.
  Status and reminder timing are native menu Pickers. Custom timing initially had its own
  button; the follow-up below consolidates it. Default Filters remains a native menu
  because it supports multiple values.
- Sidebar symbols fit within a 14-point square inside the 22-point tile.
- All visible labels reuse existing localized strings. No website feature names or
  published screenshots changed.

## Validation results

- `make build-mac`: passed, including a final build after follow-ups. Existing
  unreachable-code warnings in LibraryView remain.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'`: 26 tests passed.
- `make test-app-sim` with the same two suite filters: 26 tests passed on the already
  booted iPad Pro simulator.
- Initial concurrent simulator test attempt failed because Xcode's build database
  was locked by the Mac test run; retried serially.
- Visual acceptance remains with the maintainer, especially middle-of-library grid
  reflow, automatic batch opening, and insertion/removal past four selected posters.

- Review artifact: `.build/mac-review/u8/AniShelf.app`; copied from the final Mac
  build and passed `codesign --verify --deep --strict`. Not launched or visually
  inspected by the agent. `git diff --check` passed.

## u8 visual feedback: timing editor and surface balance

The maintainer found the separate Custom button redundant, its editor still styled
for iOS, the poster fan visually left-heavy, and the notes/person cards too white.

- Custom is now a choice in the native timing picker. Its action opens the editor
  without persisting a sentinel value. A saved non-preset offset remains a distinct
  selected item, so Custom can reopen the editor even for an existing custom value.
- Mac timing editing uses a compact labeled form with numeric hour/minute fields,
  steppers, and bottom Cancel/Save buttons with keyboard shortcuts. It edits only
  the custom offset; Use Default belongs to the parent picker. iOS keeps its prior
  presentation. Existing localized labels are reused.
- Poster spacing and rotation are reduced; the whole fan is shifted by half its
  horizontal spread so its bounds are centered. The direction and selection order
  remain stable. Shadows are lighter.
- Notes and person-card captions use a subtle adaptive neutral fill and fine
  borders rather than opaque white backgrounds. iOS notes styling is unchanged.

These are source changes awaiting the maintainer's visual acceptance.

Validation for this visual follow-up: `make build-mac` and `make build` both
passed. No additional unit tests were added for these presentation changes.
`.build/mac-review/u9/AniShelf.app` is the new Mac review artifact and passed strict
signature verification. `git diff --check` passed; the agent did not launch or
visually inspect it.
