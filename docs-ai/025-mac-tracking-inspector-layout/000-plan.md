# 025 — Mac tracking inspector layout: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-17 |
| Origin | Maintainer request on `feat/native-macos`: redesign the Mac tracking section, "particularly dissatisfied with the dates/status tracking subsection". A first label-grid version was reviewed in the running app as "still … kind of messy"; this plan records the row design that replaced it. |
| Related | [020-native-macos](../020-native-macos/000-plan.md), [024-inspector-entry-switch](../024-inspector-entry-switch/000-plan.md) |

## Background

The Mac inspector's tracking card stacked a score card, a nested `Tracking`
disclosure, a centered segmented status picker, and two `.stepperField` date pickers.
`AnimeEntryDatePickers` bound `dateStarted ?? .now`, so an unset date rendered as
today's date at 50% opacity, and both dates showed regardless of status. The
Hide/Track Dates button shared the status caption row and looked like a label.

A first redesign put score, status and a one-line date "timeline" in a
trailing-aligned label grid. In the running app it still mixed two label systems
(grid labels vs. captions above Episode Progress and Notes), three control text
sizes, a floating Clear button, a lone blue "Hide Dates" link, and an icon-only
rewatch badge, and it did not match the stat card directly above it.

## Goals

- One rule for the whole Mac card, using the stat card's row geometry
  (`DetailStatCard.compactTile`): body-size label leading, control trailing, dividers
  between rows. Labels use the primary color, as in System Settings.
- Unset dates read as "Not Set" placeholders; a click opens a calendar with Today and Clear.
- Date Started / Date Finished rows follow the status; hiding dates is a context-menu action, and a single Dates row with Track Dates replaces them while hidden.
- Episode progress and notes join the same row style.

### Non-goals

- iOS layout, the `AnimeEntry` model and schema, the status-change date suggestion
  alert, and the Mac batch panel's date toggle.

## Design / approach

- `EntryDetailTrackingSection` (Mac): renders `EntryDetailTrackingEditor` directly in
  one glass panel with the stat card's insets; the disclosure stays iOS-only.
- `EntryDetailTrackingEditor.macBody`: Score, Watch Status (context menu: Rewatching
  checkmark while watching), Times Rewatched (`EntryRewatchCountRow`, field + stepper),
  `EntryDateRows`, episode progress, Notes (200 pt editor). The iOS rewatch badge and
  popover (`EntryRewatchControls`) are iOS-only.
- New `EntryDetailMacTrackingRows.swift`: `EntryTrackingRow`, `EntryDateRows`,
  the date token and calendar popover, and the status-to-visible-dates rule.
- `EntryScoreCard(isInline:)`: compact stars; clicking the current star clears, and the
  context menu offers Clear.
- `EntryEpisodeProgressControl` (Mac): label and season menu leading, count and
  stepper trailing, full-width slider below.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Stat-card row style | Matches the card above; the earlier trailing-label grid mixed with caption headers and looked messy. |
| Primary-color row labels | Rows hold controls; macOS (System Settings, grouped `Form`) keeps such labels primary and reserves gray for sublabels and values. Gray labels copied from the stat card made the controls look disabled. The stat card keeps its gray labels as a read-only stat display. |
| Remove the nested Tracking disclosure on Mac | The Mac keeps it open anyway and its title outranked Score. |
| Calendar popover with Today and Clear | Bigger target than stepper arrows and a path back to `nil`. Rejected: `.stepperField` plus a clear button. |
| Hide Dates in the date rows' context menu | A switch row was tried and judged not worth a row. While hidden, one Dates row with a Track Dates link brings them back. |
| Hide empty dates that do not fit the status | Plan to Watch shows only Date Started; a date with a value always shows. |
| Rewatch count as a field + stepper row; Rewatching flag in the status row's context menu | Replaced an icon badge opening a popover with one toggle and one stepper, an iOS pattern. The count row matches episode progress. The flag is normally set by the rewatch prompt, so a context-menu checkmark covers corrections; the middle segment already reads Rewatching. Earlier tries: badge under, then beside, the label. The same toggle is a checkmark item in the menu bar's Anime menu (`MacLibraryCommands`), acting on the single selected entry. Rejected: an inline checkbox on the count row (two controls in one row). |
| Graphical picker without a focus ring | The calendar takes focus in the popover and drew an accent ring around the month; `.focusEffectDisabled()` removes it. |
| Clear score by clicking the current star | Removes the floating Clear button; the context menu keeps an explicit Clear. |

## Validation and acceptance criteria

- `make build-mac` and `make build`; `make run-mac` for the maintainer's visual pass.
- Manual: placeholders for unset dates; pick, Today and Clear; Dropped locks dates;
  the switch keeps stored dates; clicking the current star clears the score.

## Amendments

None yet.
