# 042.016 — Timeline date options

## Change

- The Timeline demo picks the date source (air date or watch dates) and the caption precision (year, year and month, full date). Defaults: air date, full date.
- Watch dates sort by the start date, or by the end date when an entry has only that. Moving an entry from Plan to Watch straight to Watched sets only the end date, so end-only entries are common.
- The caption shows an air date as one date and watch dates as a range: closed when both ends exist ("Jun 2 – 10, 2024"), otherwise open on the missing side ("Jun 2, 2024 –", "– Jun 10, 2024"). The shape tells the two sources apart, so the screen carries no label. Open ranges reuse the separator Foundation's interval format uses for that language, such as ～ in Japanese. Dropped entries get no special treatment.
- Timeline sorts by the full date at any precision and leaves out entries without the chosen date. The demo shows how many entries have it, and applies its entry limit after that filter.
- Snapshot entries add optional watch start and end dates and the information-language locale. The saver formats dates in that locale: air dates in UTC, watch dates in the local time zone. Older snapshots still open but must be republished to get the new fields. Schema version and shipping layouts are unchanged.
- Watch status is now published in the information language, like every other text field. It used to follow the app's UI language.

## Refs and validation

- `ScreenSaverDraft` (options), `Timeline.swift` (`TimelineDateText`, order, and caption), `ScreenSaverSnapshotBuilder` (dates and locale).
- `swift test --package-path ScreenSaverKit --filter 'timeline|manifestRoundTrip'` passed.
- `make test-app-mac` with only `ScreenSaverPublisherTests.seasonUsesParentTitleSelectedPosterAndInfoLanguage()` passed. The parentheses in that test name need a quoted `APP_ONLY_TESTING_ARGS`.
- `ScreenSaverDemo --capture <folder> --layouts timeline --dates watch` frames showed closed and open Japanese ranges.
