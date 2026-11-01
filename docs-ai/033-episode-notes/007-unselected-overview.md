# 033.007 — Show the overview with no selected chip

## Context

Once every inline editor had a bottom-right All button
([006](006-return-to-all.md)), the All chip only repeated that navigation and
took space in the compact strip. The maintainer approved removing it and showing
the overview with no scope chip selected.

## Change

- Show Overall and episode chips only. Tapping an unselected chip opens its
  editor; tapping the selected chip returns to the All overview. Other selection
  paths (overview rows, the expanded reader, the episode picker, and creation
  controls) select directly and never toggle.
- The default-scope rule, iOS swipe order (All, Overall, then episodes), and the
  editor's All return button are unchanged.

This supersedes the visible All chip described in the compact-strip amendment;
the plan, action record, and that amendment are corrected in place.

## Refs

- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryNotesSection.swift`

## Validation

`make build` and `make build-mac` passed. No simulator was booted, so runtime
interaction was not checked. No automated tests were added.
