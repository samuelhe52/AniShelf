# 034.005 — The category sieve

| Field | Value |
| --- | --- |
| Status | Implemented — maintainer accepted |
| Anchor date | 2026-10-30 |
| Origin | The maintainer asked for a more engaging "Describe a Category" flow (2026-10-30), approved a written proposal, then a clickable HTML prototype ("Butter smooth") |

## Context

"Describe a Category" ([004](004-settings-and-described-categories.md)) ran in three
steps after the description: an indeterminate "Reading your request…", a progress bar
("Checking 40 of 135 anime"), then Batch Add's result rows listing only the matches.
The wait is 7 s on a provider with 8 batches in flight, 30–40 s with one in flight
(004's measurements), and longer on-device. The waiting screen also hides data the
run already has:
- the plan, about 2 s in: the name, the filters, and the criterion;
- every candidate, with its poster, before any check runs;
- each batch's matches, as they return;
- the rejections. The model's stable misses (【推しの子】 for music, 004 "Current
  state") cannot be fixed inside the flow.

The prototype was a local HTML file outside the repository, and it is not kept.

## Change

The progress and review steps merge into one view, the **sieve**. The sheet becomes two
steps: describe, then sieve. The failure screen stays.

1. **Plan chips.** While the plan runs, the sieve shows the quoted request with skeleton
   placeholders for the name and chips. When the plan arrives, the name types in as an
   editable large title, and the plan's filters appear as chips: kinds, watch statuses,
   favorites, score bounds, air-year bounds, finish-year bounds, and the criterion.
   `unsupportedRequest` shows as a struck-through chip, with the existing "Not
   applied" line under the chips.
2. **Poster grid.** Every candidate appears at once, dimmed, in a poster grid sorted by
   name. Batches in flight shimmer. When a batch returns, its matches light up with a
   checkmark and a small pop, staggered within the batch. Rejections fade back. A
   sticky glass capsule reads "N found · X of Y checked", with the checked fraction as
   its fill.
3. **Toggle while checking.** Any resolved poster toggles with a tap. Positions stay
   fixed until the check ends, so a tap never hits a moving target.
4. **Stop and Review.** The bottom action while checking. It cancels the run and marks
   the unresolved candidates unchecked.
5. **Settle.** When the check ends (or stops), the included posters (matches, plus
   anything the user turned on) stay in the grid under "In this category". The others
   shrink away into a collapsed **Not included** row, and the remaining posters close
   the gaps. (The plan had them fly into the row; see "Maintainer review" below.)
   With Reduce Motion on, this one settle cross-fades instead (maintainer decision,
   2026-10-30).
6. **Not included.** Expanding the row shows the rejected and unchecked posters. Tapping
   one adds it without moving it. Unchecked posters carry an orange badge, and an
   inline **Check Again** reruns the check over them only. The rechecked matches
   move up into the grid.
7. Create Category is unchanged, and still the only write.

This reverses one 004 decision, "the review lists matches only, each with a toggle".
The maintainer approved the new behavior in the prototype.

### Model and runner

- `CategoryQueryPlan` gains `criterionLabel`, a short label for `semanticCriterion` in
  the language of the request. The criterion stays English for the check prompt
  (004), so without this field a Japanese request would show an English chip. Every
  field stays required for strict provider schemas. `AIFixtureProvider`'s plan reply
  adds the field.
- `AIBatchRunner.run`'s `progress: (Int, Int)` callback is replaced by
  `events: (AIBatchEvent) -> Void`, with two cases: `.started(identities)` when a batch
  is sent, and `.finished(identities, result)` when a batch reaches its final result.
  A card that fits no batch counts as a finished failure. Results still merge in batch
  order, so the outcome does not depend on which request returns first.
- `CategoryDraftModel` builds the proposal as soon as the plan arrives, holding the
  plan for the chips. Each candidate carries:
  - a verdict: pending, checking, match, rejected, or unchecked;
  - its acceptance;
  - whether it is listed in "In this category".

  `.checking` drops its counts, which the view derives from the proposal. New methods
  are `stop()` and `recheck()`. `uncheckedCount` and `unsupportedRequest` become
  derived values. Every batch failing still shows the error screen.
- `AIProposal.Item.value` becomes `var`, so a candidate's verdict can change in place.

### Views

- `CategoryDraftSheet.swift` keeps the steps, title, toolbar, and bottom bar. The
  title reads "Describe a Category" until the plan arrives, then "New Category".
  Edit Description is in the toolbar throughout the sieve.
- New files:
  - `MyAnimeList/Sources/Views/Library/Categories/CategoryDraftSieve.swift`: the
    header, capsule, grids, and Not included section;
  - `MyAnimeList/Sources/Views/Library/Categories/CategoryDraftPosterCell.swift`;
  - `MyAnimeList/Sources/Views/Gadgets/FlowLayout.swift`: wraps the chips; the app
    has no wrapping layout yet.
- **Mac:** the same sieve in the 480×560 sheet. While checking, Stop and Review takes
  the confirmation slot; afterwards, Create Category does.
- **Not ported from Batch Add:** the rows' overviews and Select All/Deselect All. The
  prototype went without them.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| One sieve view instead of progress then review | The wait shows the result forming, and the review needs no extra step. Polishing the progress screen alone keeps the wait empty. |
| Poster grid instead of Batch Add rows | About 4× the titles per screen; a category is judged by recognition, not overviews. Rows stay in Batch Add. |
| Keep rejections, collapsed | Recovers the model's recall misses inside the flow. Collapsed by default, so the result still reads as the matches. |
| Fixed positions until the end | Taps stay reliable, and the one reflow at the end gives the movement its meaning. Live reordering was rejected. |
| A `criterionLabel` plan field | A localized chip, and a visible check that the request was read correctly. Showing the request text was rejected, because it already appears above the name. |
| Reduce Motion cross-fades only the settle | The settle is the one large spatial movement. The maintainer confirmed it, as the project rules require. |
| An event callback in the runner | One callback carries both progress and per-batch results. Keeping `progress` alongside it was rejected as two overlapping APIs. |

## Validation and acceptance criteria

- Focused tests:
  - `AIFoundationTests`: the runner emits `started`/`finished` covering every identity
    exactly once (adapting the existing progress test).
  - `SmartFeaturesTests`:
    - verdicts and acceptance after a run with a failed batch;
    - `stop()` marks unresolved candidates unchecked and reaches the review;
    - `recheck()` sends only unchecked cards and lists the new matches;
    - the existing apply tests still hold.
- `make build-mac`, and `make test-app-sim` with `APP_TEST_ONLY` for the two suites.
- Simulator run with a fixture library and the fixture provider. Check plan chips,
  streaming, toggling, Stop and Review, the settle, Not included, Check Again with
  `#flaky`, Create, and Reduce Motion.
- `ja` and `zh-Hans` for every new string. Remove catalog entries the change leaves
  unused.

## Implementation notes

These came up during the build, beyond the plan above:
- **Fixture provider:** `AIFixtureProvider` now reads three filter words, so a fixture
  launch shows filter chips: "movies" sets the kind, "finished" the watch status, and
  "favorites" the favorites filter.
- **`#flaky` window:** a `#flaky` prompt now fails for 15 s from its first failure. That
  outlasts the runner's retries (about 11 s at most), so the run still counts the batch
  unchecked.
  - Before, the same prompt failed forever. Check Again repacks the unchecked cards in
    the same order into byte-identical batches, so in fixture launches it could never
    recover them.
  - Real provider failures are not keyed to the prompt.
- **Dimming:** only the artwork and the caption dim. The badges and outlines stay
  legible on a dimmed poster. Narrowed again after the maintainer review below.
- **Settle timing:**
  - The settle waits 0.4 s, so the last batch's ripple lands before the posters move.
  - The status capsule fades out in 0.15 s, so it does not overlap the "In this
    category" header that fades in at the same place.
- **Strings:** the catalog dropped the strings the old review used: the progress count,
  the row counts, the unchecked footers, the old "Not applied" line, and "Select All".
  "Deselect All" stays, because the Mac commands use it.

## Maintainer review (2026-10-30)

The maintainer tried the build on their own library and reported four problems:

1. **Gray layer.** Unselected posters should not be grayed. Now only the check itself
   dims a poster: waiting, and fading back once rejected in the main grid. After a
   toggle, and under Not included, posters keep full color; the badge alone shows
   selection.
2. **Flash on deselect (intermittent).** A frame-by-frame look at the maintainer's
   recording showed the poster pale for two frames, full color, then fading. The pale
   frames were `.plain`'s pressed highlight, which shows only when a press lasts long
   enough to render. Posters now use a press style that only scales slightly.
3. **Blank poster.** A matched, selected poster was laid out and tappable but invisible,
   including its caption and badge.
   - First guess: the matched-geometry flight into the pile. The flight was removed,
     but the blank still reproduced. The grid's empty slot belonged to "Harvest Blade
     Paradox Chronicle".
   - The suspected cause (wrong; see "Follow-up: blank poster, again" below): that
     poster sat below the visible area during the check, so the lazy grid had no cell for it. The settle moved it up, and the grid built its cell during
     the animated update with an insertion transition that never finished.
   - Fix: grid cells have no insertion transition. The arrival fade is now an
     `hasArrived` state with a per-cell delay, so a cell built later reads it as
     already shown.
   - Three consecutive runs then settled with no gaps, checked down to the Not
     included row.
   - The pile is now a static fan of the last three posters, and rejected posters
     shrink and fade as they leave.
4. **No transition from the plan to the check.**
   - The plan's arrival now animates: the placeholder cross-fades into the name and
     chips, and the posters fade in staggered from the top.
   - The status capsule swaps "Reading your request…" for the counts with a blur, not a
     cross-fade, so the two lines never overlap as one garbled line.

### Follow-up: selection like the library grid

The maintainer then asked that selection and deselection simply reuse the library grid's
multi-selection (`LibraryGridItem`). That supersedes items 1 and 2 above:
- **Unselected look:** an unselected poster dims to 0.48 opacity and 0.95 scale, with
  `.bouncy(duration: 0.18, extraBounce: 0.1)`. This applies to a deselected match, a
  rejection under Not included, and an unchecked poster.
- **Badge:** the top-trailing badge stays (the maintainer asked to keep it). It shows a
  filled check when selected, an empty circle when not, and an orange "!" when the poster
  could not be checked. It sits outside the dimming. The ring on posters added by hand
  and the dashed outline are gone.
- **Tap:** the poster is no longer a `Button`, whose touches a scroll view delays. Like
  the library card, it toggles from a `TapGesture` attached with `.simultaneousGesture`,
  plus an accessibility action.
- **One redraw per toggle:** the cell is `Equatable` on its data, through `.equatable()`,
  so a toggle redraws only that poster instead of every cell. The maintainer reported it
  smooth afterwards and accepted the timing against the library grid.
- **Unchanged:** the check's own dimming of waiting and rejected posters.

Simulator check (Japanese, fixture library): a deselected match and the Not included
posters showed the library's unselected look, and nothing flashed.

### Follow-up: blank poster, again

The maintainer hit the blank poster again on the iPad, on their own library: the second
slot of the settled grid, still in the accessibility tree as selected.
- **Repro:** a scripted run on the booted iPad Pro 13-inch simulator, with
  `-library-fixture 135` and the fixture provider. It never blanked with a warm poster
  cache (0 of 15 runs). With the fixture's Kingfisher cache deleted before each launch,
  about one cold run in nine left a first-row slot blank. The three earlier clean runs
  proved nothing.
- **Symptoms:** the whole cell is undrawn. A tap still toggles it, and it stays blank
  afterwards.
- **Ruled out:** each of these variants still blanked at least once in 15 cold runs:
  - no grid-cell transitions at all, with leaving posters faded in place first;
  - that, plus no `hasArrived` arrival fade.
- **Cause:** the cell's `keyframeAnimator` for the match pop. Without it, nothing else
  changed, 35 cold runs had no blank, against 4 of 37 with it. Why a keyframe-animated
  cell stays undrawn when the lazy grid builds it during the settle is not understood.
- **Fix:** the pop is a plain `scaleEffect` on a `pops` state, which a match sets after
  the cell's ripple delay and resets 0.18 s later. The grid transitions and the arrival
  fade stay as they were.

## Refs

- Model and runner:
  - `MyAnimeList/Sources/AI/CategoryDraftModel.swift`
  - `MyAnimeList/Sources/AI/AIBatchRunner.swift`
  - `MyAnimeList/Sources/AI/CategoryQueryPlan.swift`
  - `MyAnimeList/Sources/AI/AIProposal.swift`
  - `MyAnimeList/Sources/AI/AIFixtureProvider.swift`
- Views:
  - `MyAnimeList/Sources/Views/Library/Categories/CategoryDraftSheet.swift`
  - `MyAnimeList/Sources/Views/Library/Categories/CategoryDraftSieve.swift`
  - `MyAnimeList/Sources/Views/Library/Categories/CategoryDraftPosterCell.swift`
  - `MyAnimeList/Sources/Views/Gadgets/FlowLayout.swift`
- Tests:
  - `AIFoundationTests/packingCountsWholePromptAtBoundaryAndMapsOnlyLocalIndices`
    (events)
  - `SmartFeaturesTests/criterionRequestKeepsEveryVerdictAndListsOnlyMatches`
  - `SmartFeaturesTests/stopReviewsWhatWasFoundAndCheckAgainListsNewMatches`

## Validation (2026-10-30)

- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/SmartFeaturesTests MyAnimeListTests/AIFoundationTests'`
  on the booted iPhone 18 Pro simulator (iOS 27.2): passed.
- `make build` and `make build-mac`: passed. One `make build-mac` run printed a
  spurious "command failed with exit code 0" line; a rerun was clean.
- `make lint`: no warnings in the touched files. Its only warnings are in
  `PlaceholderTextEditor.swift`, which this change does not touch.
- **Simulator run, in Chinese, with `-library-fixture 135`:**
  - "music movies I finished" showed the chips 电影 and 已看完 plus the criterion,
    then 4 matches and 9 under Not included.
  - Tapping a Not included poster added it with the ring, and the count went from
    4 to 5 selected.
  - "music anime #flaky" streamed results ("23 found · 112 of 135 checked"), then
    left 56 unchecked. Check Again brought Not included from 117 to 108.
  - Create Category made a 27-anime category and dismissed the sheet.
  - A recorded run showed the posters sliding and leaving the grid at the settle.
    With Reduce Motion on, the settle was a cross-fade.
- **After the maintainer review, in Japanese, with the same fixture:**
  - A held deselect (0.35 s) kept full color throughout, with no flash.
  - The arrival animated, and the capsule blurred between its two lines.
  - Three runs of "music anime" settled with no invisible posters.
  - Not included posters showed in full color.
  - The focused tests, `make build-mac` (the spurious line again on the first run,
    clean on rerun) passed.
- **Blank-poster follow-up, on the iPad Pro 13-inch simulator (iOS 27.2):**
  - 20 cold-cache runs with the `pops` scale: no blank slot.
  - `make build-mac` passed.
- **Maintainer check on the native macOS app (2026-10-30):** the sieve's layout and
  animations, including the new pop, checked out.
- **Not checked:**
  - the Apple Intelligence backend and real providers;
  - the iPad layout (before the blank-poster follow-up);
  - the settle on a library large enough for hundreds of rejections.
