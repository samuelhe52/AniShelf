# 033.006 — Return to All from a note editor

## Context

On 2026-10-27, the maintainer requested a small return control while editing an
episode note, placed where Expand appears in the inline All overview. The
maintainer then extended the same control to the Global/Overall editor.

## Change

- Show an All button with `arrow.uturn.backward` at the bottom-right of the
  inline episode and Overall editors on iOS and macOS for entries supporting
  episode notes, including a selected empty episode draft. Use the overview
  footer's caption-weight styling and horizontal inset.
- The button selects the existing All scope through `select(.all)`, which also
  scrolls the selected capsule into view through the existing scope observer.
- Keep the bounded notes-box height. The footer reserves space beneath the
  editor rather than covering editable text.
- Show the control whenever episode-note support makes All available. Movie
  editors do not gain this footer. The separate episode-note sheet is unchanged.
- Reuse the existing All localization, including Japanese `すべて` and Simplified
  Chinese `全部`. No localization catalog change is needed.

## Refs

- Source: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`,
  the inline `editor` footer and `entryNotes.showAll` accessibility identifier.
- Existing localized title: `MyAnimeList/Resources/Localizable.xcstrings`.
- Related navigation behavior: [005-swipe-scope-navigation.md](005-swipe-scope-navigation.md).

## Validation

`make build` and `make build-mac` passed, including reruns after extending the
button to Overall. `git diff --check` and documentation
link checks passed. No further visual checks were requested; placement and button
behavior are not runtime-verified. No automated tests were added or run for this
local UI wiring change.
