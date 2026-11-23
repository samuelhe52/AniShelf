# 042.015 — Timeline chronology and pacing

## Context

The Timeline draft sorted entries by the year it parsed from a display label and used the entry ID within a year. At the shortest hold, a new pan started before the previous one had settled. A focus change also scheduled animations for posters whose emphasis did not change.

## Change

- The snapshot carries the optional air date in the existing UTC ISO 8601 format and a full-date label in the library's information language. The fields are additive; schema 3 and shipping layouts are unchanged. Snapshots from older builds still open, but Timeline needs a new publication to pick up the dates.
- Timeline sorts by air date, breaking ties by stable entry ID. It leaves out undated entries and skips unreadable posters without leaving a gap. Posters stay evenly spaced. Year badges mark the first displayed entry of each new year; a `↻` badge marks the return to the earliest displayed entry. The focused caption shows the full date.
- The first poster gets a settled hold immediately. Each later step takes a 2.6 s pan plus the configured hold. The caption and focus finish by the end of the pan. The strip pans as a unit; only the two posters changing focus animate their scale and shade.
- Timeline remains a demo layout. Shared wash scheduling and additional date modes are out of scope.

## Refs and validation

- `ScreenSaverKit/Sources/ScreenSaverKit/Drafts/Timeline.swift`, `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverManifest.swift`, `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSnapshotBuilder.swift`.
- Focused ScreenSaverKit tests passed: `manifestRoundTrip` and `timelineOrdersFullAirDatesAndMarksReadableYearBoundaries`.
- The native app test `ScreenSaverPublisherTests.seasonUsesParentTitleSelectedPosterAndInfoLanguage()` passed. The first filter, without `()`, selected no tests.
- A native playback smoke run with a fixture and a 2 s hold measured 2.01 s before the first pan and 4.61 s between the first two pan starts. Exactly 2 of 24 poster layers animated their focus. The settled layer render showed the year and wrap badges and the full date under the focused title.
