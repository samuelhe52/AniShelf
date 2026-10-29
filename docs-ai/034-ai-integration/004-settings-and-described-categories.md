# 034.004 — Smart Features settings and described categories

## Context

On 2026-10-29 the maintainer asked for the Settings UI and feature 1. They answered an
interactive plan with these decisions:
- the UI name is "Smart Features";
- the page shows when no backend can work, with the reason;
- the model list holds the checked models plus a custom ID ("Allow custom, but note the
  risks");
- "Describe…" goes in the iOS category manager, the Mac sidebar and the Mac category
  manager, not in the multi-selection Category menu;
- the review lists matches only, each with a toggle.

## Change

**Settings.** A new `smartFeatures` destination adds a "Smart Features" hub row,
showing the active backend or "Off". The page also appears in the iPad workspace and
the Mac Settings window, which share `LibraryProfileSettingsView`.
`LibraryProfileSmartFeaturesSettings` lists:
- the backends, each with its availability reason;
- per provider (OS 27 only): a model menu with the suggested models and "Custom
  Model…", key controls that show only the last 4 characters, and a connection
  test;
- a disclosure of what the provider receives.

A custom model shows a warning: AniShelf did not check it, it must support structured
output, and it can be slower, cost more or answer less accurately.

`AISettingsModel` caches availability, models and key suffixes, so a redraw never
reads the Keychain. A change of model or key invalidates a connection test that is
still running, so the test cannot report on the old configuration. It posts `aiConfigurationDidChange`, and the entry points reread
the backend when it arrives. The DEBUG smoke request and the page's Test button share
`AIConnectionCheck`.

**Described categories.** `CategoryDraftModel` runs the flow from the plan:
1. One `CategoryQueryPlan` request.
2. `candidates(in:)` in code.
3. If a criterion remains, `AIBatchRunner` with `AIBatchSelection` over one card per
   candidate.
4. A review, then Apply.

Details:
- **Plan record:** every field is required, and an empty list, 0 or `false` means
  "no filter", because strict provider schemas reject optional properties.
- **Genres:** genres are judged by the model through `semanticCriterion` and never
  filter locally (see the redesign below). Corrected in place: a first version used
  local `CategoryGenreGroup` filters with a combined-genre check, which the
  real-library evaluation showed to be lossy.
- **When the model checks:** `needsCheck` is true exactly when a criterion exists.
- **Score and dates:** lower and upper score bounds, first-air years and finish years
  all exist.
- **Snapshots:** `start()` snapshots every visible entry into `CategoryDraftEntry`, so
  the run never reads a live model after an await.
- **Partial failure:** failed batches leave their candidates out and show as a count
  in the review. If every batch fails, the error shows instead.
- **Apply:** creates the category and adds the accepted anime through
  `LibraryBatchAction.category`, then saves. Presenters with a library window
  (`LibraryView`, `MacLibraryView`, the Mac sidebar) switch that window to the new
  category. Presenters inside Settings do not.

**Privacy.** `PRIVACY_POLICY.md` gains an Optional Smart Features section and the
OpenAI and OpenRouter services. Its effective date is unchanged until the release
that ships the feature.

Rejected: optional fields in `CategoryQueryPlan`, because of strict schema
compatibility.

**Review corrections.** A dual review (two Codex reviewers and a debate thread) found
six P2 issues before commit, and all are fixed:
- unknown-genre entries were checked without the genre;
- genres combined with OR;
- stale connection-test results;
- live models were read after an await;
- combined TV genres could decide alone;
- there was no upper score bound.

The genre, snapshot, score and test-token changes above are those fixes.

**Stress-test corrections.** A simulator-free stress run (Codex gpt-6.1-terra, xhigh,
9–17 live requests) found three issues, all fixed:
- **Empty category from a stale review:** Apply could create an empty category
  after the accepted anime were deleted or hidden. Apply now matches them against
  the visible library first, refuses if none remain, and the sheet says so.
- **Silent key-removal failure:** a refused Keychain deletion gave no feedback.
  `removeKey` now returns the result, and the page shows an alert.
- **Haiku rejected every request (HTTP 400):** `anthropic/claude-haiku-5.5` failed
  every structured request. Diagnosis by curl: Anthropic rejects the `x-order`
  keyword that `GenerationSchema` adds to each object. The vendored adapter now
  sends the `response_format` schema without it (its header records the
  modification). Tool parameter schemas still carry `x-order`; tool calling stays
  untested.

**Real-library evaluation and genre redesign.** A Codex run on a scratch copy of the
maintainer's library (135 visible entries, 15 requests, 65 live requests) showed
that the local genre filter caused most errors:
- TMDb has no TV ID for romance, music, plain fantasy or plain science fiction, so
  those requests excluded every TV series: やがて君になる, ホリミヤ, けいおん!,
  ガールズバンドクライ and others.
- Incomplete tags excluded titles such as 新世界より.
- The plan had no field for the finish date, so "finished in 2020 or later" lost
  its date constraint silently.
- The check accepted borderline fantasy and sci-fi titles.

On the maintainer's approval (2026-10-29):
- the plan dropped `genreGroups`, and genres, themes and studios now go into
  `semanticCriterion`;
- the local filter keeps only the user's own data, with a new finish-year range;
- `unsupportedRequest` surfaces any other user-data constraint in the review;
- cards carry production companies and genres labeled "TMDb genres";
- the check prompt says a missing tag is not evidence against a match, and it
  leaves out loose fits and unsure cases (the recheck below revised which).

The cost is that every genre request goes through the model check; the flow review
below has the measured figures. The privacy policy and the in-app disclosure now
list studios.

**Recheck.** A second run (20 requests, 150 live requests) found the romance, music,
mystery, finish-date and studio misses fixed, with errors left only in the model's
judgment. It also found these, now changed:
- The blanket exclusion of dreams and afterlives cost fantasy titles whose premise
  is exactly that, such as 君の名は。. The check now asks whether the premise or main
  story meets the criterion, and excludes only single episodes, a story within the
  story, metaphors, loose resemblances, and unsure cases.
- An English request got its name and warning in Spanish. On-device language
  detection was tried and then dropped; see the flow review below.
- With no matches, the review dropped the "Not applied" warning; the empty screen
  now shows it.
- The 160-character overview often stopped before the premise (全修。, ATRI). Every
  non-empty overview in the library has kana, so it costs about a token per
  character: median 196 characters, p99 499. Cards now keep up to 500, which holds
  99% whole. For 135 entries a genre request takes 16 check calls instead of 11,
  about the same as no cap.
- Four of six seasons stored an empty overview rather than none, so their cards
  carried no overview. Empty now falls back to the series' overview, as missing did.

**Flow review.** The third run (300 live requests) recovered 全修。 as fantasy and
removed planetarian, but cards that did not change also flipped (Violet Evergarden
TV as fantasy, Angel Beats! as sci-fi). So single runs measure model variance as
much as code changes. The maintainer then reviewed the whole flow (2026-10-29) and
changed three parts:
- **Studios:** cards list every production company. With only the first three,
  SHIROBAKO lost P.A.WORKS (fourth) and was missed twice.
- **Language:** `NLLanguageRecognizer` detection is gone, and the plan again asks for
  "the language of the request". Detection read mixed-script requests such as
  P.A.WORKS制作のアニメ as English at 0.95, and the review lets the user edit the
  name anyway.
- **Parallel batches:** `AIBatchRunner` runs up to `maximumConcurrentBatches` at
  once and merges results in batch order. Providers allow 8; Apple stays at 1,
  because the on-device model answers one response at a time. That is an assumption,
  not a measurement. Parallel requests save time, not tokens: 135 entries still
  take 16 check calls, and 800 take about 95. Eight requests in flight make a
  provider rate limit (HTTP 429) more likely, and those batches count as unchecked.

**Cost and time.** Measured on OpenRouter with 135 entries: a genre request makes 1
plan call (about 2 s) and 16 check calls. With 1 in flight it takes 32–39 s, with 8
about 7 s. GPT-6 Luna costs about $0.004 per request from reported token usage.
Scaled from that, 800 entries take about 95 calls, 30 s and $0.02. No HTTP 429
appeared in 570 calls. Apple Intelligence was not eligible on the test Mac, so the
sequential Apple setting is still unmeasured.

**Model choice.** A Codex reviewer labeled every entry for 8 requests before seeing
any output (one reviewer, with borderline entries excluded). Each model then ran
each request twice:

| Model | Precision | Recall | Same decision across runs |
| --- | --- | --- | --- |
| GPT-6 Luna | 96% | 96% | 98% |
| DeepSeek V4.1 Flash | 79% | 96% | 96% |
| Claude Haiku 5.5 | 53% | 94% | 89% |

- **Haiku contradicted its cards.** It put 49 titles under Kyoto Animation whose
  cards name other studios.
- **DeepSeek confused fantasy and science fiction.**
- **All three missed 君の名は。 as fantasy in every run.**
- **Tuning didn't close the gap.** Temperature 0 and greedy sampling did not help,
  and greedy once dropped the criterion. Low reasoning raised Haiku to 67% and
  DeepSeek to about 91% precision. It took 4 times as long (26–28 s), because the
  2,048-token reply reservation splits a library into about 75 batches.

On the maintainer's approval, GPT-6 Luna is the only suggested OpenRouter model, and
the others remain custom choices.

Gemini 2.5 Flash-Lite failed every plan call with HTTP 400 ("function calling config is
set without function_declarations"). The vendored client always sent `tools: []` and
`tool_choice: "auto"`, and it now sends neither field when a request has no tools.
With the fix, it scored 78% precision and 92% recall at 5 s and about $0.003 per
request, so it stays a custom model. Its errors repeated across runs, such as Frieren and
CLANNAD as sci-fi. It also reported 71 reasoning tokens over 258 calls, although
reasoning was requested off.

## Refs

- `MyAnimeList/Sources/AI/AISettingsModel.swift`
- `MyAnimeList/Sources/AI/CategoryQueryPlan.swift`
- `MyAnimeList/Sources/AI/CategoryDraftModel.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSmartFeaturesSettings.swift`
- `MyAnimeList/Sources/Views/Library/Categories/CategoryDraftSheet.swift`
- Entry points: `MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryManagerSheet.swift`,
  `MyAnimeList/Sources/Mac/MacLibraryCategoryManagerSheet.swift`,
  `MyAnimeList/Sources/Mac/MacLibrarySidebar.swift`
- Tests: `MyAnimeList/Tests/MyAnimeListTests/SmartFeaturesTests.swift`

## Validation

- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/SmartFeaturesTests MyAnimeListTests/AIFoundationTests MyAnimeListTests/LibrarySortingAndDeletionTests'`
  on the booted iOS 27.2 simulator: passed.
- `make build`, `make build-mac` and `make lint`: passed.
- **Simulator run, in Japanese, on the simulator's 137-entry library, with OpenRouter
  and `openai/gpt-6-luna` injected through DEBUG:**
  - The hub row read "スマート機能、OpenRouter".
  - The page listed Apple Intelligence as unavailable ("the model is still
    downloading"), and Test reported a working connection.
  - Describe ("ファンタジー世界のアニメ") filtered to 50 candidates and checked them.
  - The review showed 29 matches with a Japanese name.
  - Edit kept the text, and Cancel changed nothing.
- **After the review fixes,** "評価4以上のコメディ" ran filters only and showed 62
  matches. OpenRouter's strict schema accepted the new plan record.
- **After the stress fixes:** the DEBUG connection check passed in the app for all
  three suggested OpenRouter models (Claude Haiku 5.5, DeepSeek V4.1 Flash and
  GPT-6 Luna). The focused tests, `make build-mac` and the neighboring library tests
  passed.
- **Apply was not run on the simulator library;** the unit tests cover it.
- **Not checked:**
  - the native macOS UI at runtime;
  - the Apple Intelligence backend;
  - OpenAI in the describe flow.

## Current state

- GPT-6 Luna scores 96% precision and 96% recall on the labeled set. Its remaining
  errors are stable: the Violet Evergarden films as fantasy, and 【推しの子】 missed
  for music. The miss shared by all three models, 君の名は。, is not yet
  investigated.
- The labels and saved runs live outside the repository, because they contain the
  maintainer's library.
