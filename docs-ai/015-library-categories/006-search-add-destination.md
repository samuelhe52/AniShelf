# 015.006 — Search add destination

## Context

On 2026-11-13 the maintainer approved an explicit category destination beside the
search add action, with a remembered default rule. Some users expect additions
from category A to join A; others collect uncategorized entries first.

## Plan (before implementation)

- Keep No Category as the initial default; offer Current Category in Library &
  Tracking settings. Store this interaction preference on the device, like search
  state, without changing CloudKit or the entry schema.
- Snapshot the originating window's category when search opens. A temporary target
  choice never changes the default rule. The regular and batch pages share one
  selection and show its destination beside their add action.
- Assign membership before saving newly created entries or explicitly restoring
  hidden entries. Visible duplicates and scaffolding that remains hidden retain
  their memberships. Revalidate targets after asynchronous metadata fetches.
  Hidden restoration was corrected during [review](007-search-add-review-fixes.md).
- Follow the chosen valid destination after adding, including A → B, and reveal
  the result through incompatible browse filters. Ordinary library-search jumps
  retain their original behavior. This supersedes the initial All fallback for
  post-add navigation; see [review corrections](007-search-add-review-fixes.md).
- Validate snapshot/default behavior, insertion and duplicate/race handling with
  focused app tests; build native macOS; launch and visually inspect the UI on
  the already booted iPhone simulator. No commits or publication requested.

## Alternatives and decisions

Always inheriting the active category would change the workflow for users who
prefer an uncategorized inbox. A mandatory confirmation dialog adds an extra step
to every add. A visible editable destination with a stable default supports both.

## Current state

Implemented locally on 2026-11-13. The maintainer subsequently authorized a local
commit after validation; pushing was not requested.

- `SearchAddCategorySelection` snapshots the opening window's category and keeps
  temporary choices in page state. `SearchAddCategoryPicker` is shared by regular
  search and batch add, including the native Mac batch sheet bar.
- Library & Tracking includes a device-local default rule, initially No Category.
  Both new choices and the destination menu have Japanese and Simplified Chinese
  translations. The iOS settings row uses the existing labeled selection capsule.
- `LibraryStore.createNewEntry` resolves membership after metadata fetches and
  before insertion or an explicit hidden-entry restoration save. Visible duplicates
  and generated hidden parents are not assigned. The shared multi-result add
  passes the target through to post-add navigation, which follows the destination.
  See [007](007-search-add-review-fixes.md) for the review corrections and validation.

## Initial validation (2026-11-13; before the corrections in 007)

- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/SearchAddCategoryTests
  MyAnimeListTests/TMDbSearchServiceBatchTests
  MyAnimeListTests/LibraryRelationshipAndConversionTests'`: passed. The result
  bundle reports 43 tests / 44 executions, zero failures or skipped tests.
  The new tests cover destination snapshots and overrides, saved memberships,
  duplicate preservation, hidden parent exclusion, staying in the matching
  category, invalidation during metadata loading, and a concurrent duplicate.
- `make build-mac`: passed on the final Swift sources; the Mac app was not launched.
- `make run-sim`: passed and launched the final Swift sources on the already
  booted iPhone 18 Pro (iOS 27.2).
- Inspected simulator screenshots of the Japanese settings row and both regular
  and batch search footers. A bare settings Picker initially hid its title; it
  was replaced with the existing labeled capsule and the result was inspected.
- Runtime: the initial default was No Category; selecting Current Category and
  opening search from 百合 selected 百合. A temporary No Category choice survived
  entry to batch add, and choosing 音乐 there survived return to regular search.
  The remembered default remained Current Category after relaunch. Read-only
  TMDb searches used Totoro / movie:8392; no library entries were added or deleted
  in the simulator. Actual persistence was verified in an in-memory test store.
- Early test compilation attempts exposed missing Xcode target membership for the
  new test file and actor hops in its Sendable test fetchers; both were corrected.
  An overlapping build hit Xcode's shared build-database lock; subsequent builds
  ran sequentially and passed. A pre-existing SmartFeaturesTests Sendable warning
  remains unrelated to this feature.
- `git diff --check`: passed.

## Limits and follow-up

Native Mac runtime, live multi-window interaction, and device execution were not
performed. No screenshot assets or existing feature names were changed; if the
website illustrates this new control, refresh its search/settings screenshots in
`../anishelf-site` when preparing the public feature announcement. That repository
was not edited. This record describes local implementation, not a published release.
