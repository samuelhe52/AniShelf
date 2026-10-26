# 033.004 — Overall default without episode notes

## Context

On 2026-10-27, the maintainer requested Overall as the default when an entry has
no episode notes. In that state, All only shows a capped version of the overall
note; opening its editor directly is more useful.

## Change

- Default to All only when episode notes are supported and at least one is
  nonempty. Otherwise, default to Overall. Empty deletion markers do not count.
- Apply the same rule on entry identity changes and after deleting the selected
  episode note. Switch from All to Overall when the last nonempty episode note
  disappears. Keep selected empty episode drafts open while typing.
- All remains manually selectable for entries supporting episode notes.
- Corrected the existing plan, action record, and compact-strip amendment in place.
  Their dated history and earlier validation results remain preserved.

## Refs

- Implementation and documentation are included in the same commit (2026-10-27).
- Source: `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`,
  including `EntryNoteScope.defaultScope(for:)`, entry-identity and empty-note
  observers, and the selected-note deletion fallback.

## Validation

During implementation, `make build-mac` and `make run-sim` passed. On the already
booted iPhone 18 Pro simulator, `sim-use` confirmed an entry with an overall note
and no episode notes opened with the Overall editor. Last-note deletion and
entry-switch behavior were checked in source, not exercised in the UI. No automated
tests were added or run for this fix. These checks were not rerun for this
documentation correction.
