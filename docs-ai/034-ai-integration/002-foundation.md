# 034.002 — Foundation slice

## Context

The maintainer authorized the “Delivery order: foundation first” slice, simulator
app tests, and one real provider request using credentials from `~/.secrets`.
Feature UI, Settings, commits, and pushes are excluded. This is a partial delivery:
the plan remains In progress, and the aggregate `001-action.md` is deferred until
the last slice, as required by the docs-ai multi-slice workflow.

## Change

| Area | Delivered behavior |
| --- | --- |
| Backends | Apple, OpenAI, and OpenRouter; Apple availability reasons are preserved; provider availability requires OS 27 and a stored key. |
| Preferences | Device-local UserDefaults for backend/model choices. An explicit usable backend wins; otherwise prefer Apple, then the first keyed provider. No UI. |
| Sessions | `AISessionFactory` contains the 26/27 split. `AIStructuredGenerator` provides a generic typed-generation seam; each call uses a fresh session. Errors are reduced to safe categories without retaining provider bodies. |
| Keys | Separate generic-password accounts under an AI-specific service, non-synchronizing and `AfterFirstUnlockThisDeviceOnly`. Update-first storage preserves an existing key when an update fails. Uses the existing injectable TMDb Keychain client. |
| Budget | Apple's positive runtime context size for every backend, with a 4096 fallback when it reports zero/nonpositive; reserves instructions, schema, output, and framing. Providers reserve 512 completion tokens with reasoning off (the default) and 2048 with it on; Apple reserves 512. (Corrected by [003-reasoning-off.md](003-reasoning-off.md); this slice originally reserved 2048 for OpenAI.) Apple uses exact counting on eligible 26.4+ systems; other paths use a mixed-script estimate with a 20% margin. |
| Batches | Generic item IDs and typed result payloads via `AIBatchOutput`; library selections and note-line assignments can share packing, index validation, and recovery. Sequential calls with progress and cancellation. Overflow, decoding failure, and truncation split once with fresh local indices; terminal failures do not block later work. Cards are serialized/estimated once, with whole-prompt checks at batch boundaries and before sending. Underestimated batches use a binary search for a fitting prefix. Invalid and duplicate output indices are discarded. |
| Review | Generic transient `AIProposal` with accepted values. No persistence or Apply implementation; later features own explicit model writes. |
| Fixture isolation | AI storage inherits the fixture Keychain client. Fixture key lookups report no AI key, and DEBUG launch injection/smoke requests are skipped. |

The adapter is vendored from `apple/foundation-models-utilities` revision
`cc3820def1fe016bc6cd49d958cd2f2a29be76a8`, verified against the local experiment's
checkout. The Apache license/header is retained. Local adaptations are 27-only
availability annotations on the adapter and its private HTTP client, app-compatible
import declarations, provenance comments, and Swift formatting/documentation
spacing. Review corrections also modify streaming completion handling to reject
truncation and missing completion signals. The header explicitly identifies the
file as modified and lists these changes, retaining the upstream copyright/license.

### DEBUG launch contract

- `ANISHELF_AI_BACKEND`: `openAI` or `openRouter`.
- `ANISHELF_AI_API_KEY`: saved through `AIProviderKeyStorage`; never written to
  UserDefaults or logged.
- `ANISHELF_AI_MODEL`: optional model override saved to UserDefaults.
- `ANISHELF_AI_SMOKE_TEST=1`: opt-in, one synthetic typed request asking for the
  integer 7. Uses injection → normal Keychain read → session factory → structured
  generator, with the shared context budget. No library content is sent.

The smoke result contains a fixed status, optional numeric HTTP/network failure
code, and the numeric Apple context size in the simulator app's Caches directory
under `ai-foundation-smoke-result.txt`. It contains no credentials, prompt, provider
body, or model output. A new smoke launch removes the previous result.
These hooks are compiled only in DEBUG. Simulator launches use `SIMCTL_CHILD_`
environment forwarding; credentials are passed in memory, never in command-line
arguments or repository files.

## Refs

- `MyAnimeList/Sources/AI/AIConfiguration.swift`
- `MyAnimeList/Sources/AI/AIProviderKeyStorage.swift`
- `MyAnimeList/Sources/AI/AIStructuredGenerator.swift`
- `MyAnimeList/Sources/AI/AIContextBudget.swift`
- `MyAnimeList/Sources/AI/AIBatchRunner.swift`
- `MyAnimeList/Sources/AI/AIProposal.swift`
- `MyAnimeList/Sources/AI/AIDebugLaunch.swift`
- `MyAnimeList/Sources/AI/Vendor/ChatCompletionsLanguageModel.swift`
- `MyAnimeList/Sources/AI/Vendor/LICENSE.txt`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- `MyAnimeList/Sources/App/LibraryFixture.swift`
- `MyAnimeList/Tests/MyAnimeListTests/AIFoundationTests.swift`
- `MyAnimeList.xcodeproj/project.pbxproj` (test target membership)

## Initial slice validation (before review corrections)

Initial slice checks on 2026-10-28 used the already booted iPhone 18 Pro simulator
(`A06216D2-8EA3-4101-9BC5-9F45356CCA35`, iOS 27.2 / 24B114). No simulator was
created or booted for this work. Test results/logs and the smoke cache are local
artifacts, not retained repository evidence.

| Check | Observed result |
| --- | --- |
| `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/AIFoundationTests MyAnimeListTests/TMDbAPIKeyStorageTests'` | Final run passed: 15 tests, 16 cases (one test takes both overflow and decoding arguments), 0 failures/skips/runtime warnings. Covers backend resolution, key storage, budget boundaries and unavailable-Apple fallback, packing, split-once recovery, local-index validation, terminal failures, cancellation, proposal selection, safe errors, and DEBUG fixture isolation. |
| `make build` | Final iOS build passed with the deployment target unchanged at 26.0. An earlier completed build emitted a compiler-driver “exit code 0 but produced no further output” diagnostic; subsequent confirmation and final builds completed without it. |
| `make build-mac` | Final native macOS build passed. The native app was not launched. |
| `make run-sim` | Rebuilt, installed, and launched the app on the same booted simulator; passed. Repeated as the DEBUG diagnostics and context-size correction were implemented. |
| DEBUG provider launch with `SIMCTL_CHILD_ANISHELF_AI_*` forwarding | One real OpenRouter typed request passed (`google/gemini-3.8-flash`, expected integer 7). Injection persisted the key through normal storage; generation reread it through the factory. No library data was used. |
| `make launch-sim` after smoke | Passed without injected environment variables, removing the secret-bearing app process environment. Stored simulator configuration remains as designed. |
| `make lint` and focused strict Swift lint | Final runs passed. |
| `git diff --check` and amendment source-path check | Passed. |
| Credential-content scan | Changed/untracked repository files and local validation logs did not contain any loaded AI credential values; the scanner reported only pass/fail. |

The first iOS build failed on the scoped-import conflict. The first simulator
test build then failed on the unguarded 27-only parsing-error type. Both were
corrected before the execution runs described below.

### Corrections found during validation

- The vendored package's scoped imports conflicted with app-wide imports; they
  were changed to ordinary imports. A separate 26-target compile error required
  guarding the 27-only `GeneratedContent.ParsingError` check.
- The first simulator execution passed four tests and then crashed on an actor
  assertion in the default async token counter. Its closure now explicitly
  preserves main-actor isolation, and the pure estimator is nonisolated. A later
  focused run passed all 14 tests / 15 parameterized cases before the context-size
  regression test was added.
- Two early DEBUG smoke launches stopped before any provider call because the
  Apple model reported a context size of 0. The first reported only a generic
  failure; safe error categories then identified the budget failure. The budget
  now falls back to 4096 for a nonpositive runtime size, and an added simulator
  test protects provider-budget construction without Apple inference.
- After that correction, one real OpenRouter request using
  `google/gemini-3.8-flash` passed typed decoding and the expected-value check
  (`value == 7`). The credential came from `~/.secrets/env/ai-tokens.env` via
  process environment → DEBUG injection → normal device-local Keychain storage.
  The smoke record confirmed `reportedContextSize=0`. The earlier two smoke
  launches made no network request because the budget check preceded generation.
- Initial focused lint found documentation-summary spacing issues, including two
  inherited vendor comments; these were corrected. One lint invocation omitted
  the recursive option and was corrected. Subsequent focused and repository-wide
  lint passed.

## Review corrections (2026-10-28)

The maintainer requested every P1–P3 finding from the dual review be fixed within
this uncommitted foundation slice. This section updates the same slice record;
the plan remains In progress, with no feature UI or Settings implementation.

| Finding | Correction |
| --- | --- |
| P1: truncated responses accepted after JSON repair | The adapter decodes `finish_reason` and throws a dedicated error for `length`, before accepting that chunk. The generator maps it to `AIError.responseTruncated`, which participates in the existing split-once retry and terminal-failure reporting. Partial results from a failed call are never added to the proposal. |
| P1: reasoning can exhaust the 512-token cap | OpenAI's default completion reservation is now 2048 tokens, covering reasoning and visible output. It is subtracted from the shared Apple context cap, reducing available input rather than exceeding that cap. Other backends default to 512; callers can explicitly override the reservation. The DEBUG smoke uses the backend default. This reduces starvation risk; it does not guarantee every model completes, so truncation still becomes a bounded failure. |
| P2: EOF without a completion signal accepted | Both transport branches require a successful finish reason (`stop`, `tool_calls`, or `function_call`) or `[DONE]`. EOF without either throws `incompleteResponse`, mapped to retryable decoding failure. Unknown/unsuccessful finish reasons also fail. `[DONE]` is explicitly tracked; a `length` error is never overridden by a later marker. |
| P2: category-only batching | `AIBatchItem`, failures, and results are generic over feature-owned IDs. `AIBatchOutput` adapts a `Generable` response into batch-local integer indices plus arbitrary typed payloads. The runner retains validated payloads alongside their original IDs. `AIBatchSelection` is one output adapter; the shared runner no longer imports DataProvider or requires library identities. Tests exercise independent string line IDs and episode-like assignment payloads through splitting and invalid/duplicate-index rejection. No note-sorting feature has been implemented. |
| P2: excessive token estimates | The fallback estimates ASCII at four characters per token, CJK/kana/Hangul at one scalar per token, and other scripts at two UTF-8 bytes per token, then adds 20%. A 500-character CJK string now estimates 600 tokens instead of 1800, before framing/schema/output reservations. Eligible Apple exact counting remains unchanged. These remain heuristics, without provider-tokenizer calibration or a measured production cost claim. |
| P3: recounting growing prefixes | Each card's JSON quoting and estimated cost are cached once. Incremental costs choose candidate batches. Whole-prompt checks validate candidates and every request, including retry halves; an underestimated candidate uses a binary search for a fitting prefix. No async exact counter call is made per appended item. |
| Apache modification notice | The vendored file's header prominently identifies local modifications, author/date, pinned upstream revision, and the streaming/availability/import/formatting changes. The upstream copyright and Apache license remain intact. |

Files changed for these corrections:

- `MyAnimeList/Sources/AI/Vendor/ChatCompletionsLanguageModel.swift`
- `MyAnimeList/Sources/AI/AIStructuredGenerator.swift`
- `MyAnimeList/Sources/AI/AIContextBudget.swift`
- `MyAnimeList/Sources/AI/AIBatchRunner.swift`
- `MyAnimeList/Sources/AI/AIDebugLaunch.swift`
- `MyAnimeList/Tests/MyAnimeListTests/AIFoundationTests.swift`
- `docs-ai/034-ai-integration/002-foundation.md`

### Review validation

| Check | Observed result |
| --- | --- |
| `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/AIFoundationTests MyAnimeListTests/TMDbAPIKeyStorageTests'` | Passed on the same already booted iPhone 18 Pro / iOS 27.2: 19 tests, 25 cases, 0 failures/skips/runtime warnings. Three tests use dynamic parameters. The earlier refactor check also passed before the additional review regressions were added. |
| Mocked provider streams through `LanguageModelSession` and the vendored transport | Both incomplete and syntactically valid JSON are rejected on `length` or missing completion signals. Explicit finish-only and `[DONE]`-only streams decode successfully. URLProtocol fixtures are immutable and selected by a reserved `.invalid` URL; they use no credentials or real network service. |
| Batch/budget regressions | Existing packing-boundary, cancellation, failure-continuation and index tests pass. Retry coverage now includes truncation. Added distinct tests cover typed assignment payloads/line IDs across retries and a 64-item batch making at most four whole-prompt counter calls (instead of per-prefix counting). Existing budget tests now protect CJK/ASCII estimate bounds and OpenAI's larger completion reservation. |
| `make build-mac` | Passed. The two existing SDK 27.2 exhaustiveness warnings in the vendored transcript conversion remain; no native app launch was performed. |
| Focused strict Swift lint and `git diff --check` | Passed after correcting a documentation-summary blank line found by the first strict lint pass. |

No live provider request or credential injection was performed for these review
corrections. The earlier successful OpenRouter smoke result above is historical;
real provider truncation/completion handling and the new OpenAI reasoning cap
remain unverified against a service. Apple inference/exact counting, OS 26 runtime,
native macOS runtime, and provider tool calling remain unverified.

## Current state and remaining work

Feature 1/category planning, local filtering, feature UI, review/apply persistence,
Settings, and feature 2/note sorting remain unimplemented. Privacy-policy changes
remain a release prerequisite. No user-facing strings or screenshots changed, so
there is no website synchronization required for this slice.

Apple inference and exact token counting require an eligible device and remain
unverified. The booted iOS 27.2 simulator reported 0 for Apple's context size;
the positive size on an eligible device remains unmeasured. OS 26 runtime
behavior, real OpenAI requests, provider tool calling, and feature interaction
flows remain unverified. The deployment targets remain iOS/macOS 26.0.

The pinned adapter emits two SDK 27.2 exhaustiveness warnings for new transcript
data/attachment cases. This slice sends text prompts only; new attachment/data
support is not implemented. The upstream unknown-case handling is retained.

The injected OpenRouter key and provider/model choice remain device-local in the
simulator's normal Keychain and UserDefaults, as designed. The app was relaunched
without injected environment variables after the successful smoke request.

No commit or push was made.
