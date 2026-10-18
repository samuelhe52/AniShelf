# 029 — Half-star scores: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-18 | Interactive HTML plan reviewed with the maintainer; Codex (gpt-6.1-sol) supplied UI alternatives. | — |
| 2026-10-18 | First Codex (gpt-6-astra, high) review: tie-break serialization, stale halves through older-build writes, tombstones, missing write paths, gestures, VoiceOver, tests. | — |
| 2026-10-18 | Maintainer replaced the `scoreHalves` mirror design with a full sync version bump. | — |
| 2026-10-18 | Second Astra review: no blocker; discard-before-fetch gap in installed builds, drag cancellation latch, snapshot JSON coverage. | — |
| 2026-10-18 | Implemented. | — |
| 2026-10-18 | Astra (medium) code review: no P0/P1. Fixed both P2s — cancelled drags now clear their preview and latch through a `@GestureState` sentinel; the Mac star row is focusable again (arrows step by a half, Delete clears). Extended the `UserEntryInfo` round-trip test to a half score. | — |
| 2026-10-18 | Per-star buttons restored at the maintainer's request, then reverted after comparing the trade-offs. | — |
| 2026-10-18 | Maintainer visual pass. A vertical swipe that starts on the stars does not scroll the sheet, so the vertical-cancel latch added no value: removed it and made the drag preview a `@GestureState`, which also covers system cancellation. Title-row number made secondary (grey); Mac row number removed. Added the DEBUG `-reset-score-hint` launch argument. | — |
| 2026-10-19 | Maintainer visual pass. Fixed the old score flashing for a frame when a drag ends; bounce limited to taps and clicks; hint moved into the title row in a smaller font; title-row number made smaller. The hint's removal was not animated; two fixes failed and were reverted, and moving the hint into the title row made it fade out. | — |

## Outcome and current state (as of 2026-10-19)

- `EntryScore` holds half-star units `2...10` and owns formatting (`formatted`,
  `exportString`) and stepping. `AnimeEntry`, `UserEntryInfo`, and
  `LibraryEntrySyncSnapshot` keep `score: Int?` as the whole stars, add
  `scoreHasHalf`, and expose `entryScore`.
- `SchemaV2_8_4` copies the 2.8.3 model family and adds `AnimeEntry.scoreHasHalf`;
  `MigrationPlan` adds a lightweight 2.8.3 → 2.8.4 stage.
- `setEntryScore` writes both fields; `updateEntryScore` stamps `trackingUpdatedAt`
  when either changes. The existing `setScore`/`updateScore(Int?)` remain as
  whole-score wrappers that clear the half.
- Sync: `LibraryEntrySyncSnapshot.currentSchemaVersion` is 3. Records carry
  `scoreHasHalf`; the CloudKit decoder honors it only when `schemaVersion >= 3`.
  Snapshot JSON and `UserEntryInfo` JSON write the key only when true; the
  tracking tie-break payload omits it unless true. Tombstones clear it. Merge, apply,
  initial apply, forced-domain apply, and bootstrap comparison carry it.
- UI: `EntryScoreCard` replaces per-star buttons with one spatial tap gesture. Touch:
  tap star N sets N, a tap on the top star toggles its half, a drag snaps to
  halves and saves on release, a grey footnote number in the title row shows the score, a hint
  ("Tap again for 3.5", `caption2`, laid over the title row's spacer before Clear so it adds no
  height) shows until the first half score (device-local `EntryScoreHalfHintSeen`; DEBUG
  launch argument `-reset-score-hint` clears it). Only taps and Mac clicks bounce the star;
  drags, arrow keys, VoiceOver adjust, and Clear do not.
- A drag's `onEnded` saves first, but the `@GestureState` reset then redraws the card
  before the parent passes the saved score back in, so the old score showed for a frame
  (traced with logging on the simulator). `droppedHalves` holds the dropped score until
  `score` changes; it is skipped when the drop equals the current score, since no change
  would clear it.
  Mac inline: pointer position picks whole or half with a hover preview; clicking the current score clears it. The Mac
  row is focusable: arrow keys step by a half star, Delete clears. Both
  expose one VoiceOver adjustable element stepping by 0.5, clamped to 1…5.
- Badges, context/batch menus (nine values), Group by Score ranks, and exports
  (`4` / `4.5`; JSON number) show halves. The library fixture gives every third
  scored entry a half without an extra generator draw.

Key files:

- `DataProvider/Sources/DataProvider/Models/Other/EntryScore.swift`
- `DataProvider/Sources/DataProvider/Models/V2/AnimeEntryV2_8_4.swift`, `SchemaV2_8_4.swift`
- `DataProvider/Sources/DataProvider/Models/Other/UserEntryInfo.swift`
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`
- `DataProvider/Sources/LibrarySync/CloudLibrarySyncClient.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailTrackingComponents.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryStore+Filtering.swift`
- `MyAnimeList/Sources/Utils/LibraryExportManager.swift`

## Deviations from plan

- `AnimeEntryMigrationDTO` is unchanged. Only older custom stages use it, and none
  targets 2.8.4.
- The touch card also dropped its per-star buttons (the plan only did so on Mac):
  a drag that ends on its starting star would otherwise also fire that star's tap.
  The maintainer briefly had the buttons restored, compared the trade-offs, and chose
  the button-free version.
- The plan's Mac hover tooltip ("Click for 3.5") was dropped; the Mac row shows only
  the stars.
- A vertical swipe that starts on the stars does not scroll the sheet (maintainer
  visual pass). The maintainer accepted this and asked to remove the cancel logic.
- The hint first sat on its own line below the stars, and its removal did not animate.
  Two fixes failed and were reverted: a local `@State` flag set inside `withAnimation`
  next to the `@AppStorage` write, and a value-based `.animation` on the card's stack
  keyed on the hint's presence (Codex, gpt-6-astra medium). Once the hint moved over the
  title row's spacer, its opacity transition played (maintainer visual check). Inference,
  not traced: the old removal changed the card's height, and the parent's layout did not
  animate it.
- Existing `Int?` score APIs stay as whole-score wrappers rather than being replaced,
  to keep call sites and tests that set whole scores unchanged.

## Validation

- `swift build` (DataProvider) — succeeded.
- `make build` (generic iOS) — succeeded.
- `make build-mac` — succeeded.
- `make test-dataprovider` (full) — all suites passed (64 and 71 tests).
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/UserEntryInfoAndLibraryStatsTests MyAnimeListTests/LibrarySortingAndDeletionTests MyAnimeListTests/LibraryExportManagerTests MyAnimeListTests/LibrarySyncCoordinatorTests MyAnimeListTests/LibraryBackupRestoreTests MyAnimeListTests/LibraryRelationshipAndConversionTests'` — TEST SUCCEEDED.
- After restoring, then reverting, the per-star buttons: `make build-mac` and `make build` succeeded.
- After the visual-pass changes: `make build-mac` and `make build` succeeded.
- After the review fixes: `make build-mac` and `make build` succeeded;
  `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/UserEntryInfoAndLibraryStatsTests'` — TEST SUCCEEDED.
- The maintainer ran a visual pass on iOS and Mac (2026-10-18). Agent-side, no
  runtime run was made. VoiceOver and haptics have no recorded check.

## Open questions

- The CloudKit production schema needs the new `scoreHasHalf` field deployed before
  a release build writes it. No repo runbook covers CloudKit schema deployment.
- Builds 1.101–1.103 can send a pending reconstruction-discard tombstone before they
  fetch and quarantine a version-3 record (see the plan's Known gap).
- The iPhone/iPad card has no keyboard focus of its own after dropping the per-star
  buttons; VoiceOver's adjustable action still works. The Mac row is focusable.
- Not covered by tests: an exact whole-score tie-break payload comparison against
  an older build, and outbox upload after a half-only edit (the clock test covers
  the prerequisite).
