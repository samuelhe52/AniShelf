# 026 — Library fixture and performance benchmarks: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-17 |
| Origin | Maintainer request (2026-10-17): there was no way to tell whether a library performance change helped or regressed, and hand-testing only covered the maintainer's ~100-entry library, while some users keep 700–800 |
| Related | [023-library-display-cache](../023-library-display-cache/000-plan.md), [014-multiselect-invariants](../014-multiselect-invariants/000-plan.md) |

## Background

Library performance has regressed twice through refactors that looked harmless
(see 014). Entry 023 moved the display list into a store-owned cache and added a
deterministic guard: `libraryDisplayComputeCount` and
`selectionTogglesReuseTheCachedDisplayList` prove that selection never
recomputes the display list. That guard covers the store. It cannot see the
view layer, for example a change that makes every row re-evaluate on each
selection tap.

Two gaps remain:

- **Scale.** Manual checks run against the maintainer's real library of about
  100 entries. Nothing exercises 800 or 2,000.
- **Measurement.** There are no automated numbers, so a before/after
  comparison relies on feel.

## Goals

- A deterministic large-library fixture, selected by a launch argument, that
  boots the real app UI with N generated entries and touches none of the user's
  real data, preferences, keychain, image cache, or iCloud.
- Automated benchmarks for the interactions users actually perform, at
  several library sizes, measuring user-perceived latency and dropped frames.
- A Make target that runs them in an optimized build and compares the
  results with a saved baseline from the same machine.

### Non-goals

- **Cold launch.** The fixture seeds an in-memory store at startup, so launch
  time would mostly measure seeding. A realistic launch benchmark needs an
  on-disk fixture store. On-disk is rejected for now: a non-in-memory
  `DataProvider` turns on the sync scheduler and the on-disk sync dirty queue
  (`LibrarySyncChangeRecorder.makeDefaultDirtyQueueStore`), which lives at the
  app's real location and could leak fixture edits into the next real sync.
- **Mac benchmarks.** `MyAnimeListUITests` builds only for iOS. The fixture
  itself works on the Mac.
- **CI and absolute thresholds.** The numbers are relative, compared on one
  machine across commits.
- **A new store-level count test.** 023 already covers it.

## Design / approach

### 1. Fixture (`-library-fixture <N>`)

Proposed file: `MyAnimeList/Sources/App/LibraryFixture.swift`, compiled under
`DEBUG || LIBRARY_FIXTURES`. When the launch argument is present:

- **Store.** `DataProvider(inMemory: true)`, seeded with N entries from a seeded
  generator (SplitMix64), so every run sees the same library. The entries vary
  in what filtering, sorting, and rows read: type (movie, series), watch status,
  score, favorite, dates, title length (Latin and CJK), overview length, and
  category membership. Fixture TMDb IDs start at 900,000,000 so they cannot
  collide with real ones.
- **Isolation.** One `UserDefaults` suite, wiped at each fixture launch, backs
  `LibraryPreferences`, `WhatsNewController`, and `AppReviewPromptController`.
  An in-memory keychain client gives `TMDbAPIKeyStorage` a fake key without
  touching the real keychain.
- **Side effects off.** `MyAnimeListApp` skips sync requests, the background
  flush, airing-reminder refresh and pruning, active-day recording, and What's
  New when the fixture is active. An in-memory `DataProvider` already keeps the
  sync scheduler and the cloud-preferences monitor off (`LibraryStore` init).
- **Categories.** The fixture creates six categories, turns categories and the
  strip on in the isolated preferences, and assigns memberships.
- **Posters without network.** Kingfisher gets its own fixture `ImageCache`
  (cleared at launch) and an `ImageDownloader` whose session uses a
  `URLProtocol` that serves generated JPEG posters for any request. The full
  path still runs: download, decode, downsample, and cache. Posters are 500×750,
  drawn from a small palette, so decoding cost matches real TMDb renditions.

### 2. Signposts

Proposed file: `MyAnimeList/Sources/Utils/LibraryBenchmarkSignposts.swift`.
`OSSignposter` intervals under subsystem `.bundleIdentifier`, category
`LibraryBenchmark`. They compile only under `DEBUG || LIBRARY_FIXTURES` and are
enabled at runtime only in fixture mode, so normal Debug runs pay nothing.

| Interval | Begins | Ends |
| --- | --- | --- |
| `SelectionUpdate` | `selectedEntryIDs` changes (`LibraryEntryInteractionState`) | First display-link frame after the change |
| `DisplayUpdate` | The display cache is invalidated (`LibraryStore`) | First display-link frame after the change |
| `DisplayUpdateAnimation` (animation interval) | Same as `DisplayUpdate` | A fixed 0.8 s later, which covers the default and `.snappy` animations |
| `BatchAction` | `applyBatchAction` starts | First display-link frame after the change |

"First display-link frame after the change" is the latency proxy. The main run
loop can't service the display link until the action, the SwiftUI update, and
the Core Animation commit have finished, so the callback marks the first vsync
at which the new state can be on screen. This is an approximation: if SwiftUI
deferred the update to a later run-loop turn, the interval would end early. The
hitch metrics on the animation interval are meant to catch that case.

### 3. Benchmarks

Proposed file: `MyAnimeList/Tests/MyAnimeListUITests/LibraryBenchmarkTests.swift`.
XCTest `measure(metrics:options:)`, with one measured action per iteration, a
fixed iteration count, and the fixture size read from the `LIBRARY_FIXTURE_SIZE`
environment variable (`TEST_RUNNER_` prefix through xcodebuild, default 800).

| Test | Action per iteration | Metric |
| --- | --- | --- |
| Selection toggle, list and grid | Tap a visible row while selecting | `SelectionUpdate` duration |
| Scroll, list, grid, and gallery | Fast swipe | `XCTOSSignpostMetric.scrollingAndDecelerationMetric` |
| Category switch (strip) | Tap the next category chip | `DisplayUpdate` duration and `DisplayUpdateAnimation` hitches |
| Batch favorite | Select visible rows (not measured), tap Favorite | `BatchAction` duration |

### 4. Tooling

- Proposed script: `scripts/library_benchmarks.py`. It reads metrics with
  `xcrun xcresulttool get test-results metrics`, writes a JSON summary
  (median and spread per test, metric, and size, plus the device), and compares
  it with a baseline. A metric that moves more than 15% gets flagged.
- `make bench-sim BENCH_SIZES='100 800 2000'` builds the Release configuration
  with `LIBRARY_FIXTURES` into its own derived data under `.build/benchmarks/`,
  runs the benchmarks once per size on the booted simulator, then summarizes
  and compares. `make bench-baseline` saves the latest summary as the baseline.
  Baselines stay in `.build/` and are not committed, because they are
  machine-specific.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Signpost intervals, not wall-clock timing in the test process | XCUITest `tap()` waits for the app to go idle, so timing it adds hundreds of milliseconds of harness overhead and animation time. Signposts measure inside the app. |
| End at the next display-link frame | Ending in `DispatchQueue.main.async` can run before the commit, because the main queue is serviced before the run loop's before-waiting observers. |
| Release build plus `LIBRARY_FIXTURES` | Debug SwiftUI and Swift are much slower in ways shipping builds are not, so Debug numbers mislead. |
| Fixture size from an environment variable | `measure` runs once per test method. A size parameter avoids multiplying the methods by three. |
| In-memory fixture | See the non-goals: on-disk would enable the real sync dirty queue. |
| `URLProtocol`-served posters | Entries without posters would skip decoding, the most likely scrolling cost. Real network would make results noisy and depend on TMDb. |
| Relative 15% threshold, local baseline | Simulator numbers reflect the host Mac. Comparing across machines or against absolute limits would be noise. |

## Validation and acceptance criteria

- `make build` and the existing focused test
  (`LibraryEntryInteractionStateTests`) still pass.
- A Debug run with `-library-fixture 800` shows the library with 800 entries,
  posters, and the category strip. The real store and preferences are
  unchanged afterward.
- `make bench-sim BENCH_SIZES='100 800'` completes on the booted simulator and
  produces a summary with a value for every benchmark metric at both sizes.
- A second run compared with the first reports deltas, which shows how noisy
  run-to-run results are.

## Amendments

None yet. Implementation deviations are recorded in [001-action.md](001-action.md).
