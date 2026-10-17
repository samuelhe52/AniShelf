# 026 — Library fixture and performance benchmarks: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-17 | Fixture launch argument, isolated startup environment, generated posters | `1622953` on `feat/native-macos` |
| 2026-10-17 | Signposts, frame monitor, UI benchmarks, `MyAnimeList-Benchmarks` scheme, `bench-sim`/`bench-baseline`, summary script | `1622953` on `feat/native-macos` |

## Outcome and current state (as of 2026-10-17)

**Fixture.** `-library-fixture <N>` (Debug, or Release built with `LIBRARY_FIXTURES`)
starts the app on `DataProvider.inMemoryFixtureBootstrap()` with N entries generated
from a fixed seed. `MyAnimeListApp.startupEnvironment()` returns the bootstrap
together with an isolated `UserDefaults` suite, wiped at each launch, for
`LibraryPreferences`, `WhatsNewController`, and `AppReviewPromptController`. Before
anything else, the fixture replaces `TMDbAPIKeyStorage.defaultKeychain` with an
in-memory client that returns a placeholder TMDb key, so every `TMDbAPIKeyStorage()`
uses it. That includes the one each `InfoFetcher()` builds in the store and in views,
and the `-reset-tmdb-api-key` path. The real key is never read or deleted. The recovery activity
gate stays blocked, which keeps the cloud-sync handler, background flush, Mac
lifecycle sync, and reminder pruning off. Sync requests, reminder refresh,
active-day recording, and What's New are also gated on `isLibraryFixture`.
Categories (six) and the category strip are turned on in the fixture preferences.
Kingfisher uses a fixture `ImageCache` and an `ImageDownloader` whose session
serves generated JPEG posters through `LibraryFixturePosterProtocol`, sized from the
TMDb rendition segment in the URL.

**Signposts.** `LibraryBenchmarkSignposts` (category `LibraryBenchmark`) emits two
intervals per interaction, each with its own signpost ID:

| Interaction | Hook | Intervals |
| --- | --- | --- |
| Selection change | `LibraryEntryInteractionState.selectedEntryIDs` `didSet` | `SelectionUpdate`, `SelectionUpdateCommit` |
| Display list invalidated | `LibraryStore.invalidateLibraryDisplay()` | `DisplayUpdate`, `DisplayUpdateCommit` |
| Batch action | `LibraryView.applyBatchAction(_:)` | `BatchAction`, `BatchActionCommit` |

`<Name>Commit` ends in a one-shot run-loop observer at `beforeWaiting`, order
2,000,001, just after Core Animation's commit observer. It measures the main-thread
cost of the update and is not frame-quantized. `<Name>` ends at the first
display-link callback after that commit, so it is quantized to frames.

**Frame monitor.** `LibraryFrameMonitor` (iOS, fixture only) runs a display link
and counts callbacks that arrive more than 1.5 frames after the previous one. The
time beyond one frame counts as hitch time. `LibraryFrameStatsElement` exposes the
running totals as the accessibility value of a 1×1, nearly transparent `UIView`
(`library-frame-stats`). The value is computed only when queried.

**Benchmarks.** `LibraryBenchmarkTests` (8 tests). The fixture size comes from
`LIBRARY_FIXTURE_SIZE`, with 10 iterations each. The custom `FrameStatsMetric` reads
the frame monitor before and after each iteration and reports Hitch Time Ratio
(ms/s) and Hitch Count.

| Test | Metrics |
| --- | --- |
| `testSelectionToggleList`, `testSelectionToggleGrid` | `SelectionUpdate`, `SelectionUpdateCommit` |
| `testScrollList`, `testScrollGrid`, `testScrollGallery` | Hitch Time Ratio, Hitch Count |
| `testCategorySwitchList`, `testCategorySwitchGrid` | `DisplayUpdate`, `DisplayUpdateCommit`, Hitch Time Ratio, Hitch Count |
| `testBatchFavoriteList` | `BatchAction`, `BatchActionCommit` |

**Tooling.** `make bench-sim` builds the
`MyAnimeList-Benchmarks` scheme (UI tests only, Release test action) with
`LIBRARY_FIXTURES` into `.build/benchmarks/DerivedData`. It runs one result bundle
per size into `.build/benchmarks/runs/<timestamp>/`, writes `summary.json`
(medians), points `.build/benchmarks/latest` at the run, and compares with
`.build/benchmarks/baseline.json`. It runs 800 entries by default, about 8.5
minutes. `BENCH_SIZES='100 800 2000'` checks scaling, and
`BENCH_ONLY='testScrollList …'` runs only the named tests. `make bench-baseline`
merges the latest run into the baseline, test by test and size by size, so a partial
run replaces only what it measured. A change is flagged only when it exceeds both
15% and an absolute floor: 5 ms for durations, 5 ms/s for hitch ratio, and 1 for
hitch count. A zero baseline (no hitches) is decided by the floor alone. Each
test's baseline keeps the device, run, and host load it came from. A baseline holds
one device, and `compare` warns when a test's baseline ran on another device or
under clearly lighter load.

**Quick mode.** For iterating on a fix, `make bench-quick` runs the same tests with
5 iterations and builds file by file (`SWIFT_COMPILATION_MODE=singlefile`), so a
one-file change rebuilds in about 12 s instead of about 60 s. One test then takes
about 70 s end to end. Quick runs keep their own derived data, `latest-quick` link,
and `baseline-quick.json` (`make bench-quick-baseline`). Their code generation differs
from the App Store build, so `save-baseline` refuses to mix modes and `compare` warns
across them. Two back-to-back quick runs of grid category switching differed by 9% in
duration but by one hitch, so hitch metrics are the steadier quick signal; wins are
confirmed with a full `make bench-sim`.

Supporting changes: accessibility identifiers `library-list`, `library-grid`,
`library-grid-item`, `library-gallery`, and `library-batch-favorite`.

Key files:

- `MyAnimeList/Sources/App/LibraryFixture.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- `MyAnimeList/Sources/Utils/LibraryBenchmarkSignposts.swift`
- `MyAnimeList/Sources/Utils/LibraryFrameMonitor.swift`
- `DataProvider/Sources/DataProvider/DataProvider+StartupRecovery.swift`
- `MyAnimeList/Tests/MyAnimeListUITests/LibraryBenchmarkTests.swift`
- `MyAnimeList.xcodeproj/xcshareddata/xcschemes/MyAnimeList-Benchmarks.xcscheme`
- `scripts/library_benchmarks.py`
- `Makefile`

## Deviations from plan

- **No system hitch metrics on the simulator.** `XCTOSSignpostMetric.scrollingAndDecelerationMetric`
  reported only `Scroll_DraggingAndDeceleration` duration (about 2.75 s, mostly
  the fixed length of the swipe gesture), and the planned `DisplayUpdateAnimation`
  animation interval produced no metric at all. Both were replaced by
  `LibraryFrameMonitor` and `FrameStatsMetric`. These see only main-thread hitches,
  not render-server ones.
- **Commit intervals added.** Display-link end times are quantized to 16.7 ms at 60 Hz.
  The `<Name>Commit` intervals give an unquantized measure of main-thread cost.
- **Next-frame timing.** The first version started the display link right away. One
  grid sample then measured 0.3 ms, meaning the callback fired before the commit.
  The display link now starts from the post-commit observer. The planned
  `CATransaction.addCommitHandler` is not public API, so a `CFRunLoopObserver` is
  used instead.
- **Dedicated scheme.** `build-for-testing` on `MyAnimeList` in Release also built
  `MyAnimeListTests`, which uses `@testable import` and fails without testability.
  `-only-testing` does not limit what gets built, and enabling testability would
  weaken the optimizations being measured. Hence the UI-test-only
  `MyAnimeList-Benchmarks` scheme.
- **Batch benchmark robustness.** With `.manuallyStart` and the shared exclusive
  signpost ID, XCTest captured intervals in only 4–6 of 10 iterations, even though
  an in-app trace showed every interval beginning, committing, and reaching its
  frame. Distinct signpost IDs raised that to 7 of 10, and a 1 s settle after the
  tap to 10 of 10. The test now measures the whole iteration; the selection setup
  emits only differently named intervals.
- **Review fixes (2026-10-17).** The first version injected the fixture keychain
  only into the app's own `TMDbAPIKeyStorage`. Each `InfoFetcher()` still built a
  system-keychain storage, so fixture metadata requests would have used the real key,
  and `-library-fixture` with `-reset-tmdb-api-key` would have deleted it. Fixed by
  the process-wide `TMDbAPIKeyStorage.defaultKeychain`; `TMDbAPIKeyStorage` is the
  only keychain user in the sources. Separately, the comparison treated a zero
  baseline as "no change", so a regression from 0 hitches could never be flagged.
  This was reproduced with synthetic summaries before the fix and rechecked after it
  (0 → 20 hitches flagged; 0 → 0.5 not flagged, below the floor).
- **Second review (2026-10-17).** Three more findings, all fixed:
  - Settings could still enable or retry cloud sync in a fixture session, because
    the gates sat only at lifecycle call sites. `LibraryStore` now takes
    `allowsCloudSync` (false for fixtures) and then creates no `LibrarySyncCoordinator`
    or scheduler. Every sync path goes through that optional coordinator, and only
    it reaches CloudKit.
  - Running `MyAnimeList-Benchmarks` straight from Xcode builds without
    `LIBRARY_FIXTURES`, so the app opens the real library. The benchmarks now
    require the fixture-only `library-frame-stats` element right after launch. If it
    is missing, they terminate the app and fail before any interaction. The failing
    path was checked by reading only; it was not exercised against the real library.
  - Merging a partial run relabeled the retained results with the new run's
    device, run, and load. Summaries and the baseline now keep provenance per test,
    a merge from another device is refused, and `compare` reports and warns per
    baseline run.
- **Third review (2026-10-17).** A test missing one metric was silently skipped
  by `compare`, and saving the baseline then erased that metric. The script now
  holds the expected metric set per test (`EXPECTED_METRICS`) and requires 10
  iterations of each. `summarize` lists problems, and `compare` and
  `save-baseline` refuse incomplete runs. Partial runs may still omit whole tests.
  This exposed an older loss: in the 100/800/2000 baseline run, both category
  switches at 2,000 entries had 8 of 10 iterations. XCTest received 3 of 4 metrics
  in one iteration and dropped it. Every measured action now settles for 0.5 s
  (1 s for batch) before the iteration ends. A rerun of both category switches at
  2,000 entries was complete. The cause of the dropped intervals is still
  unconfirmed.
- **Fourth review (2026-10-17).** In a fixture session, Settings could still remove
  the real airing-reminder subscriptions and pending notifications, because
  `AiringReminderCoordinator.shared` used standard defaults and the system
  notification center. While a fixture is active (`LibraryFixture.active`, set
  before any shared service exists), `shared` now uses a manager on the fixture's
  defaults suite, with a notification center that schedules nothing and no TVMaze
  lookups. A sweep of the other shared services found one more real-data path:
  backup restore writes the backup's settings into the standard defaults. It now
  fails in fixture launches. The TVMaze confirmed-mapping store still writes to
  standard defaults, but only under fixture TMDb IDs (900,000,000 and up), so it
  cannot overwrite a real mapping. Separately, `summarize` now registers every test
  case that ran (`xcresulttool get test-results tests`) and records failed tests.
  A test that ran without measurements is therefore incomplete, not omitted, and a
  run with no results is refused.
- **Runtime.** Three sizes took about 25 minutes. Halving the iterations to 5 was
  rejected: recomputing medians from each half of three existing 10-iteration runs
  would have falsely flagged 4–6 metrics per run (about 10%). Instead the default
  became one size, with opt-in sizes and `BENCH_ONLY`. Per test at one size: batch
  about 2 min 5 s, each scroll test about 1 min 8 s, category switches about 43 s,
  selection about 28 s.
- **Isolation is not total.** `-PersistedScrolledID` and `-LibraryViewStyle` are
  passed through the argument domain, but view-level `@AppStorage` writes (for
  example, changing the view style picker during a manual fixture session) and the
  scroll position still go to the standard defaults domain. A fixture scroll
  position left behind is ignored at the next real launch, because no real entry
  has that identity.

## Validation

- `make build`, `make build-mac`: passed.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryEntryInteractionStateTests MyAnimeListTests/LibrarySortingAndDeletionTests'`:
  both suites passed (iPad Pro 13-inch (M5) simulator, iOS 27.0).
- `make run-sim` with `-library-fixture 800 -LibraryViewStyle list`: the library
  showed 800 entries, the category strip, and generated posters. The posters took a
  few seconds to appear on the first screen.
- `make bench-sim BENCH_SIZES='100 800'`, run twice with the first run saved as the
  baseline: 8 tests passed per size, and the comparison reported **0 changes
  beyond the noise thresholds**. Most medians moved by 7% or less. Hitch counts
  moved by about half a hitch. This run predates the batch-benchmark fixes, so its
  batch metrics were incomplete.
- Final `make bench-sim` (100, 800, 2000) after the batch fixes: 24 tests passed.
  Compared with the first baseline, **0 changes beyond the noise thresholds**. It is
  saved as `.build/benchmarks/baseline.json` (run `20261017-055042`, not committed).
  The 800-entry batch median from this run (BatchAction 217 ms over 10 of 10
  iterations) agrees with the incomplete first run (209 ms).

- After the review fixes: `make build`, `make build-mac`, and
  `TMDbAPIKeyStorageTests` passed. The zero-baseline and merge behavior were checked
  with synthetic summaries. The key fix was verified by reading the startup order
  only. It was not exercised with `-reset-tmdb-api-key`, which would delete the
  simulator's real key if the fix were wrong.
- After the second review: `make build`, `make build-mac`, and the
  `LibrarySyncCoordinatorTests`, `LibraryCloudSyncPreferencesTests`,
  `LibraryEntryInteractionStateTests`, and `TMDbAPIKeyStorageTests` suites passed.
  `make bench-sim BENCH_ONLY='testSelectionToggleList'` passed the fixture check.
  Provenance merging and the cross-device refusal were checked with synthetic
  summaries.
- `make bench-sim` (800 only, new default) took 9 minutes, and all 8 tests passed. It
  flagged 7 hitch "regressions", with every duration 7–12% higher. A two-test rerun
  (`BENCH_ONLY`) was flagged again. The host load average was 10–15 throughout
  (other apps and agent sessions), and the fixture app logged no TMDb or network
  errors. These are attributed to host load, not code: the only app change was
  the keychain wiring. The baseline was left unchanged, and summaries now record
  the 15-minute load average and warn on a mismatch.

Measurements from the final run (Release, iPad Pro 13-inch (M5) simulator, iOS 27.0,
medians):

| Metric | 100 | 800 | 2000 |
| --- | --- | --- | --- |
| Selection toggle, list (frame / commit) | 30 / 15 ms | 31 / 16 ms | 30 / 17 ms |
| Selection toggle, grid (frame / commit) | 33 / 27 ms | 33 / 27 ms | 33 / 25 ms |
| Category switch, list (commit, hitch ratio) | 93 ms, 97 ms/s | 103 ms, 100 ms/s | 132 ms, 114 ms/s |
| Category switch, grid (commit, hitch ratio, hitches) | 40 ms, 82 ms/s, 4.5 | 108 ms, 339 ms/s, 14.5 | 134 ms, 344 ms/s, 13.5 |
| Scroll list / grid / gallery (hitch ratio) | 27 / 30 / 20 ms/s | 27 / 32 / 16 ms/s | 25 / 29 / 16 ms/s |
| Batch favorite, 6 rows (commit) | 149 ms | 203 ms | 321 ms |

## Closure (2026-10-17)

The performance work is closed. The maintainer checked an 800-entry fixture on an
iPhone simulator by hand and saw no performance problems. Profiling with
`/usr/bin/sample` (`xctrace --attach` hangs because Developer Mode is off on this Mac)
found that on the iPad Pro simulator, which connects a hardware keyboard by default,
grid category switches spent about 23% of main-thread time in UIKit keyboard focus:
with nothing focused, `UIFocusSystem` searches the whole SwiftUI grid again after
each hierarchy change. iPhones never pay this cost, so later benchmarks should run on
an iPhone simulator. The saved baselines in `.build/benchmarks/` are still the iPad
ones, renamed `baseline-ipad-pro-13.json` and `baseline-quick-ipad-pro-13.json`; no
iPhone baseline has been saved. `make bench-quick BENCH_ONLY=<test>` (about 70 s, 5
iterations) is the fast loop; its hitch metrics are steadier than its durations.

## Open questions

- **iPad keyboard focus cost.** The grid category switch slowdown with library size
  (14 late frames per switch at 800 entries against 4 at 100 on the iPad simulator)
  is at least partly the keyboard-focus search above. Avoiding it would only help
  iPad users with a keyboard attached. Not pursued.
- **Batch favorite takes 150–320 ms for six rows** on the iPad simulator and grows
  with library size, which suggests the save and refresh path, not the six writes.
  Not investigated.
- **The cause of the dropped batch intervals is unconfirmed.** The settle works, but
  the other tests may be susceptible if their iterations get longer.
- **Host load sensitivity.** Simulator results move with the Mac's load. A full
  rerun after a restart (`20261017-153208`, 15-minute load 11.5) read 20–50% higher
  than the table above with power and thermal state normal; the cause is
  undetermined.
- **Unresolved review findings (round 5).** Committed at the maintainer's request
  with three P2 findings open: the fixture reminder manager's `reloadState` still
  calls `updateBackgroundRefreshRequest()`, which cancels the real background
  refresh request; `compare` returns before `require_complete` when no baseline
  exists, and `summarize` exits 0 on incomplete runs; and a relative `BENCH_DIR`
  breaks the `latest` symlink. A separate bundle ID for benchmark builds was
  proposed as structural isolation.
- **Network with the placeholder key is untested.** The fixture blocks sync,
  reminders, and What's New, and serves posters locally, but other TMDb requests
  (for example, a metadata refresh) would go to the network with the placeholder
  key and fail. None was observed during the benchmarks.
