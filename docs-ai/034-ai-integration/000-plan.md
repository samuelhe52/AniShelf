# 034 — AI integration: Plan

| Field | Value |
| --- | --- |
| Status | In progress |
| Anchor date | 2026-10-28 |
| Origin | Maintainer direction from a 2026-10-25 discussion with Codex, refined with Claude Code on 2026-10-28 (OS split, context budget, providers, App Intents reuse) |
| Related | [015-library-categories](../015-library-categories/000-plan.md), [033-episode-notes](../033-episode-notes/000-plan.md), [016-settings-hub](../016-settings-hub/000-plan.md), 019-app-intents (unmerged; only on `feat/app-intents-spotlight`) |

## Background

Some library chores take many manual steps that a language model could collapse
into one instruction plus a review. The first example is building a category from a
description ("Group all fantasy anime"), which today means finding every matching
entry and selecting it by hand. A second is sorting the single lines users have
collected in an entry's overall note into the episode notes from
[033](../033-episode-notes/000-plan.md).

The maintainer's bar is a clear gain in efficiency or experience. Generic chat, or
anything the existing UI already does well, doesn't qualify; importing
recommendation lists was rejected because batch add already matches titles well.

Apple's Foundation Models framework gives one Swift interface for sessions, typed
output (`@Generable`), tools and streaming. The iOS 27.2 SDK shows the split that
shapes this plan:

| iOS/macOS 26 | iOS/macOS 27 |
| --- | --- |
| `LanguageModelSession`, `SystemLanguageModel`, `Generable`, `GenerationSchema`, `Tool`, `Transcript` | `LanguageModel` protocol, `LanguageModelExecutor`, `LanguageModelSession(model: some LanguageModel, …)` |
| A session runs only on `SystemLanguageModel` (Apple Intelligence) | Any `LanguageModel`, including third-party providers |
| `contextSize` back-deployed as a constant 4096; `tokenCount(for:)` from 26.4 | `contextSize` reported by the model at runtime |

The October 13 provider experiment (`~/projects/foundation-models-openrouter`,
outside this repository) ran `ChatCompletionsLanguageModel` from
`apple/foundation-models-utilities` on macOS 27. OpenAI, OpenRouter and Bailian
passed plain, typed and streaming generation. DeepSeek and Moonshot failed typed
generation, and tool calling was not tested.

## Goals

- A shared AI foundation that every later feature reuses: backend selection,
  provider keys, a context budget, batching, and a review-then-apply flow.
- **Feature 1: create a category from a description**, built end to end.
- **Feature 2 (next, designed here and built after feature 1): sort an entry's
  overall-note lines into episode notes.**
- On iOS/macOS 26, AI features appear only where Apple Intelligence is available.
  On 27, OpenAI and OpenRouter are offered as well. The deployment target stays
  26.0.
- Every backend gets the same context budget, the Apple on-device limit. The tasks
  are simple, and small models retrieve poorly even when the entries are already in
  context, so AniShelf does the retrieval, filtering and batching itself.
- Nothing the model proposes is written until the user reviews and applies it.

### Non-goals

- Chat, general agents, or open-ended tool loops. If later work becomes agentic,
  that is the point to revisit the context cap.
- Recommendations, review drafting, summaries, theme grouping.
- Exposing AI actions through App Intents, Siri or Spotlight.
- Supporting providers beyond OpenAI and OpenRouter (DeepSeek and Moonshot
  explicitly excluded), or a developer-owned backend key.
- Note sorting across the whole library in one pass (see feature 2).

## Design / approach

New code lives under a proposed `MyAnimeList/Sources/AI/` folder unless noted.

### Backends and availability

- Proposed `AIBackend`: `.apple`, `.openAI`, `.openRouter`.
- Proposed `AIAvailability` decides which backends are usable:
  - `.apple` requires `SystemLanguageModel.default.availability == .available`.
    The unavailable reason, for example `deviceNotEligible`, is shown in Settings.
  - `.openAI` and `.openRouter` require iOS/macOS 27 and a stored key.
  - When no backend is usable, AI entry points are hidden rather than disabled.
- Proposed `AISessionFactory` is the only place that knows about the OS split.
  - On 26 it always builds `LanguageModelSession(model: SystemLanguageModel.default, …)`.
  - On 27 it builds `LanguageModelSession(model: some LanguageModel, …)` with either the
    system model or a `ChatCompletionsLanguageModel`.
- Proposed `AIStructuredGenerator` is a small protocol around "instructions + prompt
  → `@Generable` value". Features depend on it, so tests inject a fake and never
  call a model.
- **Provider adapter:** `apple/foundation-models-utilities` declares iOS/macOS 27
  as its minimum, so Swift Package Manager will not link it into a 26.0 target.
  - Vendor `ChatCompletionsLanguageModel.swift` (one self-contained file of
    948 lines that imports only Foundation and FoundationModels, Apache 2.0) at
    the experiment's pinned revision `cc3820de` as proposed
    `MyAnimeList/Sources/AI/Vendor/ChatCompletionsLanguageModel.swift`.
  - Keep its license header, mark it `@available(iOS 27, macOS 27, *)`, and record
    the source revision in the file.
- **Default models** are the experiment's passing ones: `gpt-5.4-mini` for OpenAI
  and `google/gemini-3.8-flash` for OpenRouter. Each can be edited in Settings.

### Provider keys and Settings

- Keys are stored in the Keychain as device-local generic-password items, one
  account per provider. This follows `MyAnimeList/Sources/Utils/TMDbAPIKeyStorage.swift`
  and reuses its injectable `TMDbAPIKeyStorageKeychainClient`, so fixture launches
  never touch real keys (docs-ai 026). Keys do not sync between devices.
- Settings adds an AI destination to `LibraryProfileSettingsDestination` in
  `MyAnimeList/Sources/Models/Library/LibraryProfileSettingsModels.swift`, mirrored
  in `MyAnimeList/Sources/Mac/MacSettingsRoot.swift`. The page contains:
  - a backend picker that marks unavailable backends with their reason;
  - key and model fields for OpenAI and OpenRouter, only on 27;
  - a connection test that runs one tiny typed request;
  - a short disclosure that third-party backends receive library titles,
    overviews and, for note sorting, note text.
- **Default backend:** Apple when it is available, otherwise the first provider
  with a key. The choice is stored per device in UserDefaults.
- `PRIVACY_POLICY.md` needs an update before release: provider requests go
  straight from the device to the provider the user picked, with the user's own key.

### Context budget and batching

- Proposed `AIContextBudget`:
  - reads `SystemLanguageModel.default.contextSize` (4096 below 27);
  - reserves room for instructions, the output schema and the expected output;
  - hands the rest to input items.
  - The same budget applies to every backend.
- **Counting:** with the Apple backend on 26.4 and later, use
  `tokenCount(for:)` for exact costs. Otherwise use a conservative estimator
  (characters per token, with CJK text weighted heavier) and a safety margin.
- Proposed `AIBatchRunner`:
  - packs items into batches that fit the budget;
  - runs them in sequence with progress and cancellation;
  - on `contextSizeExceeded` or a decoding failure, splits the batch once and
    retries;
  - after that, reports the batch as failed without blocking the others.
- **Item references:** items in a batch are identified by a short integer that is
  local to the batch. The runner maps it back to `LibraryEntryIdentity` and drops
  any index the batch didn't contain, so the model never sees or invents real IDs.

### Review-then-apply

- Each feature produces a proposal, which is shown in a review sheet with a toggle
  per item. Apply writes the accepted items through existing model APIs and saves
  once. Cancel discards the proposal.
- Model output never writes to SwiftData directly.

### Delivery order: foundation first

The first slice is the foundation alone, with no user-facing UI:
- backends and availability, `AISessionFactory`, `AIStructuredGenerator`, and the
  vendored adapter;
- key storage;
- `AIContextBudget` and `AIBatchRunner`;
- a generic proposal type for review-then-apply.

Until the Settings page exists:
- the selected backend and models are stored in UserDefaults with no UI;
- DEBUG builds read a provider key and model from launch environment variables
  and save them through the normal key storage, so a real provider request can
  run on the simulator.

The code stays in the app target, because it needs `LibraryStore` and the Keychain
client. Feature UI and Settings come in later slices.

### Feature 1: category from a description

- **Entry point:** the category manager's New Category action
  (`MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryManagerSheet.swift`
  and `MyAnimeList/Sources/Mac/MacLibraryCategoryManagerSheet.swift`) becomes a
  menu with "Name…" (today's flow) and "Describe…". The AI option appears only
  when Library Categories is on and a backend is usable.
- **Plan step:** one call turns the instruction into a `@Generable`
  `CategoryQueryPlan`:
  - a suggested category name;
  - structured filters: type, watch status, favorite, score range, year range, and
    TMDb genre IDs chosen from a list given in the instructions;
  - an optional `semanticCriterion`, left empty when the structured filters fully
    answer the request.
- **Local filter:** the structured filters are applied in code to visible library
  entries, which gives the candidates. Genre IDs come from each entry's cached
  `AnimeEntryDetail.genreIDs`, written when the entry is added and on metadata
  refresh. TMDb's TV genres are broad ("Sci-Fi & Fantasy", "Action & Adventure"),
  and every entry carries Animation, so genre filters narrow the candidates but
  rarely answer the request alone.
- **Classify step:** only when a `semanticCriterion` exists. Candidates are packed
  into batches as compact cards: batch index, display name, original name, year,
  type, localized genre names, and a truncated overview. Each batch returns
  `matchingIndices: [Int]`. Reasons are left out to save output tokens.
- **Review:** an editable name, plus the matches with toggles. Apply calls
  `LibraryStore.createCategory(named:)` and then
  `AnimeEntry.updateCategoryMembership(_:isMember:knownCategoryIDs:)` for each
  accepted entry, then saves.
  - Category membership is not part of `UserEntryInfo`, so an open entry detail's
    Discard cannot undo it.
  - Undoing a mistake means deleting or editing the category.
- **Cost on a large library:** an 800-entry library at roughly 80 tokens per card
  is about 20 classify calls under a 4096 budget. Progress and Cancel are required,
  and the local filter should usually shrink the set first.

### Feature 2 (next): overall-note lines into episode notes

- **Per entry, from the entry detail's notes section.** The detail holds a
  Discard baseline (`EntryDetailSession.originalUserInfo`) that includes `notes`
  and `episodeNotes`. Any write made outside the session to an open entry is
  undone by Discard: the baseline adopts outside changes only when a missing
  parent appears (`EntryDetailView`'s `supportsEpisodeNotes` handler).
  - Running inside the detail and applying results as ordinary unsaved edits
    keeps Save and Discard meaning what they mean today.
  - A whole-library pass would need a baseline broadcast for notes, like
    `LibraryEntryTrackingChange` on `feat/app-intents-spotlight` does for tracking
    fields. That is deferred.
- **Flow:**
  - Split the overall note into lines or sentences.
  - For each line, the model proposes an `EpisodeNoteAnchor`, or "keep in overall
    note".
  - The prompt includes the season and episode structure and, where cached, the
    episode titles from `AnimeEntryDetail.episodes`.
  - The review step shows each line with its proposed episode.
  - Apply appends accepted lines to the target episode notes, through the owner
    rules in `DataProvider/Sources/DataProvider/Models/Other/EpisodeNote.swift`,
    and removes them from the overall note.
  - An existing episode note is extended, never overwritten.
- **Before building:** test tool calling with OpenAI and OpenRouter, but only if
  episode lookup turns out to need a tool instead of an inline episode list.

### Reuse from `feat/app-intents-spotlight`

None for features 1 and 2. That branch's search matcher does substring matching,
and its intent library context guards headless runs, which in-app flows don't
need. If a later feature needs keyword retrieval, copy over `de239c2`
(`LibrarySearchMatcher` tiers) on its own. Never merge the branch wholesale.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Foundation Models as the only interface | Maintainer decision: one API for Apple Intelligence and third-party providers. Rejected: a separate HTTP client per provider with hand-written JSON decoding, which duplicates schema handling and adds a second code path. |
| OS split: 26 = Apple only, 27 = Apple + providers | Custom providers need the 27-only `LanguageModel` protocol. Rejected: raising the deployment target to 27 (drops 26 users for no gain), and skipping Foundation Models on 26. |
| Providers: OpenAI and OpenRouter | Maintainer decision. Both passed typed and streaming generation. DeepSeek (rejects `json_schema`) and Moonshot (fenced output) are out of scope. |
| One context budget (Apple's limit) for every backend | Maintainer decision: the tasks are simple, and small models retrieve unreliably even when entries are in context. Same batching behavior on every backend. |
| Plan step, then local filter, then classify | Lets structured requests skip the model's per-entry judgment, and keeps genre and status logic in tested code. Rejected: sending the whole library to the model, which can't fit and retrieves poorly anyway. |
| Batch-local integer indices | Fewer tokens than UUIDs, and invented references are easy to reject. |
| Vendor the adapter file | The package's iOS 27 minimum blocks linking. Rejected: writing our own adapter (more code to own), and waiting for Apple to lower the package minimum. |
| Keys device-local | Matches the TMDb key. iCloud Keychain sync is a possible later option. |
| Feature 2 inside the entry detail | Avoids the Discard baseline conflict without new broadcast plumbing. |
| Hide AI entry points when no backend is usable | Many users will never configure a provider, following the opt-in spirit of [015](../015-library-categories/000-plan.md). |

## Validation and acceptance criteria

- **Unit tests through the fake `AIStructuredGenerator`:**
  - budget packing at the limit;
  - split-and-retry on overflow;
  - dropping out-of-range indices;
  - the `CategoryQueryPlan` local filter (genre, status, type, year, score);
  - applying a reviewed proposal creates the category and its memberships.
- **Feature 2 tests:**
  - accepted lines move into the right episode notes;
  - an existing episode note is extended, not overwritten;
  - Discard after Apply restores the original notes.
- **Builds:** `make build` and `make build-mac`.
- **Simulator:** an OpenRouter run of feature 1 with the maintainer's key, on an
  already booted iOS 27 simulator. The simulator can't run the Apple model on a
  host that isn't eligible.
- **The Apple-backend path needs an eligible device.** Until one is available, its
  behavior is recorded as unverified.

## Open questions

- The runtime `contextSize` on iOS/macOS 27 is unmeasured; the plan reads it at
  runtime and assumes 4096.
- The user-facing name for the feature in Settings and menus ("AI", "Assistant",
  or something else) has to be decided before the strings go into
  `Localizable.xcstrings`.
- Whether to show a short reason per match in feature 1's review. The current plan
  says no, to save tokens; revisit after trying it.
- How well the Apple on-device model judges `semanticCriterion` for anime is
  unknown until it can be tested on an eligible device.

## Amendments

- Updated 2026-10-28: Delivered the foundation slice without feature UI or Settings; validation and remaining boundaries are recorded in [002-foundation.md](002-foundation.md). The aggregate `001-action.md` is deferred until the last slice, following the multi-slice workflow.
