# 033.006 — Return to All from a note editor

## Context

On 2026-10-27, the maintainer requested a small return control while editing an
episode note, placed where Expand appears in the inline All overview. The
maintainer then extended the same control to the Global/Overall editor.

## Change

- Show a small All button at the bottom-right of the inline episode and Overall
  editors on iOS and macOS for entries supporting episode notes, including a
  selected empty episode draft, styled like the overview's Expand footer.
- The button selects the existing All scope directly.
- Keep the bounded notes-box height. The footer reserves space beneath the
  editor rather than covering editable text.
- Show the control whenever episode-note support makes All available. Movie
  editors do not gain this footer. The separate episode-note sheet is unchanged.
- Reuse the existing All localization.

## Refs

- Source: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`.
- Related navigation behavior: [005-swipe-scope-navigation.md](005-swipe-scope-navigation.md).

## Validation

`make build` and `make build-mac` passed. Placement and button behavior are not
runtime-verified. No automated tests were added.
