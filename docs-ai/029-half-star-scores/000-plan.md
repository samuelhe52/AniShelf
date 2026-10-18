# 029 — Half-star scores: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-18 |
| Origin | Maintainer request: "Overtime I've found fractions like 3.5 and 4.5 to be useful additions, but I can't think of a good way to add that to the current UI..." Design reviewed in an interactive HTML plan, then two Codex (gpt-6-astra, high) reviews. |
| Related | [009-cloud-sync-correctness](../009-cloud-sync-correctness/000-plan.md), [015-library-categories](../015-library-categories/000-plan.md), [023-library-display-cache](../023-library-display-cache/000-plan.md) |

## Background

User scores are `Int?` in `1...5` end to end: the SwiftData model
(`AnimeEntry.score`), `UserEntryInfo`, the CloudKit record, the export rows, and every
score menu. The maintainer wants half steps (1.5 … 4.5) without making the existing
five-star control harder to use.

## Goals

- Scores from 1 to 5 in steps of 0.5. The lowest score stays 1; 0.5 is not valid.
- Whole-star taps keep working exactly as today.
- Every surface that shows or sets a score supports halves: the detail score card,
  the Mac tracking row, badges, context and batch menus, Group by Score, exports.
- Half scores sync through iCloud without older builds silently corrupting them.

### Non-goals

- No score sort or filter, and no separate "half stars" setting.
- The TMDb score, settings record, and tombstone versions do not change.

## Design / approach

**Value type.** A new `EntryScore` (`DataProvider/Sources/DataProvider/Models/Other/EntryScore.swift`,
proposed) stores half-star units `2...10` and exposes `wholeStars`, `hasHalf`, `value`,
formatting, and stepping. App code reads and writes only `entry.entryScore`.

**Storage.** New `SchemaV2_8_4` copies the 2.8.3 model family and adds
`AnimeEntry.scoreHasHalf: Bool = false` next to `score: Int?`. Migration from 2.8.3 is
lightweight. `setScore`/`updateScore` write both fields; `updateScore` advances
`trackingUpdatedAt` when either field changes, so a half-only edit still reaches the
sync outbox, which watches clocks.

**Touch (iPhone/iPad).** A tap on star N sets N. A second tap on the top star toggles
its half (4 → 3.5 → 4). A mostly horizontal drag across the stars snaps to halves with
a selection haptic and saves on release; a drag that starts vertical is cancelled
until release so the sheet still scrolls. The title row shows the exact number. A
short hint teaches the second tap until the first half score. VoiceOver reads the
stars as one adjustable control stepping by 0.5, clamped to 1…5.

**Mac.** The pointer position over a star picks the whole or the half, with a hover
preview. One spatial tap gesture owns the row (no per-star buttons); a click on the
current score still clears it.

**Display.** Badges and menus show "4" or "4.5". Menus list the nine values. Group by
Score ranks halves between wholes. Exports write a number (`4`, `4.5`).

**Sync.** `LibraryEntrySyncSnapshot.currentSchemaVersion` goes 2 → 3, so every entry
record this build writes is version 3. The record keeps `score` (whole stars) and adds
`scoreHasHalf`. The CloudKit decoder honors `scoreHasHalf` only on records with
`schemaVersion >= 3`, because an older build can still write a version-2 record that
leaves the key behind. Snapshot JSON and merging keep the flag unconditionally. The
tie-break payload encodes the flag only when true, so whole-score payloads stay
byte-identical. Tombstones clear the flag.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Second tap + drag on touch | No new controls and full-size targets. Rejected: a numeric chip with −/+ (Codex's first pick; easy to find but an extra tap and more UI), split-star half targets (18 pt targets on iPhone), a "+½" pill (a sixth control). |
| Pointer half-picking on Mac | A pointer is precise enough for half targets, and hover makes it self-teaching. A second click is already "clear" on the Mac row. |
| `score` + `scoreHasHalf` in SwiftData | Lightweight migration with no data copy. Rejected: replacing `score` with `scoreHalves: Int?`, which needs a custom stage that copies `score × 2`. |
| Full sync version bump to 3 | Maintainer's deliberate choice: older builds (1.101–1.103) quarantine version-3 records, never upload over them, and show the existing "unreadable records" item that suggests updating; 1.92–1.100 fail the import. Rejected: (a) a `scoreHalves` mirror kept readable by older builds with a floor/mismatch rule — an older build's edits can resurrect a stale half; (b) adding a clock stamp or repair uploads to fix (a) — judged too complex to maintain; (c) bumping only half-score records — gentler for old devices but adds a "lowest version that can carry this record" rule every later bump must follow. |
| Lowest score 1 | Matches the existing range; 0.5 adds no value the maintainer asked for. |

## Validation and acceptance criteria

- DataProvider tests: half-score record round trip at version 3; a version-2 record
  ignores a leftover flag; tombstones clear the flag; whole-score tie-break payload is
  unchanged; snapshot JSON keeps the flag (old JSON decodes false; a v2 snapshot merged
  with a v3 one keeps the half); a half-only edit advances the tracking clock;
  2.8.3 → 2.8.4 migration keeps whole scores.
- `make build`, `make build-mac`, and focused test runs.
- Runtime check of the touch and Mac gestures when a simulator is already available or
  the maintainer runs the app.

### Known gap

A 1.101–1.103 device can send a pending reconstruction-discard tombstone before it
fetches and quarantines a version-3 record
(`MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator+Pipeline.swift`).
New code cannot fix installed builds.

## Amendments

None yet.
