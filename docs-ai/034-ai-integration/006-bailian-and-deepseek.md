# 034.006 — Bailian and DeepSeek

## Context

The [000 plan](000-plan.md) limited cloud providers to OpenAI and OpenRouter and
excluded DeepSeek because it rejects `json_schema`. On 2026-11-20 the maintainer
compared GPT-6 Luna with two cheaper routes on the Describe a Category benchmark
([runbook](category-eval.md)), then approved adding both as fixed model choices.

The run used the reconstructed dataset, 8 requests × 2 rounds, 1,030 calls in all,
with no failed or unchecked batches. It was scored against the original labels, then
rescored offline, with no new calls, after the maintainer corrected 30 borderline
labels. Corrected macro scores:

| Route | Precision | Recall | Run cost |
| --- | --- | --- | --- |
| OpenRouter `openai/gpt-6-luna` | 95.1% | 89.3% | $0.057 (reported) |
| Bailian `qwen3.8-flash` | 87.5% | 90.7% | ¥0.38 (estimated) |
| DeepSeek `deepseek-flash` | 83.0% | 91.0% | $0.057 (estimated) |
| Bailian `deepseek-v4.1-flash` | 82.6% | 91.1% | ¥0.78 (estimated) |

All four routes reached about the same recall. Luna's lead is precision: it adds far
fewer wrong entries, and wrong entries are what the user has to remove by hand, so it
stays the recommendation. DeepSeek through Bailian scored the same as native DeepSeek
at about twice the cost, so the app does not offer it.

The runner used for this run packed batches for Bailian and DeepSeek with a slightly
smaller budget than for Luna, so 10 of the 48 non-Luna plans were checked in different
batches than Luna's would have been. The app packs every cloud backend the same way,
and the runner was fixed to match afterward. The runner also under-reserved the schema
by 17 estimated tokens, so its batches could hold one card more than the app's, on every
route alike. That is fixed too. The run was not repeated; part of the precision gap may
come from the batching rather than the model. No saved plan set a score bound, so the
runner's score-filter bug, since fixed, did not affect these results.

## Change

- **Backends:** `AIBackend` gains `.bailian` (`qwen3.8-flash`) and `.deepSeek`
  (`deepseek-flash`), offered on iOS, iPadOS, and macOS 27 or later like the other
  cloud providers, with the model menu and a custom model ID as for OpenAI and
  OpenRouter. (Superseded: see Follow-up below for the model lists.) Each provider stores its own key in
  the device-local Keychain and uses the existing connection check.
- **Endpoint:** Bailian uses the China (Beijing) endpoint `dashscope.aliyuncs.com`,
  the only Model Studio region in mainland China. Model Studio keys work only in their
  own region, so the Bailian key prompt asks for a Beijing-region key. Other regions
  (Hong Kong, Singapore, US, Frankfurt, Tokyo) are not supported: the benchmark
  covered only Beijing, and the target users are in mainland China, where OpenAI and
  OpenRouter are unreachable.
- **Structured output:** both routes send `response_format: {type: "json_object"}`
  instead of a JSON schema, with thinking disabled (`enable_thinking: false` on
  Bailian, `thinking: {type: "disabled"}` on DeepSeek) and `max_tokens` instead of
  `max_completion_tokens`. Each output type (`AIConnectionCheck.Response`,
  `CategoryQueryPlan`, `AIBatchSelection`) adopts `AIJSONExample`, and its example
  object is appended to the instructions. Foundation Models still decodes the reply
  into the same typed value as on the other backends.
  - Rejected: putting the generated JSON schema in the prompt. DeepSeek streamed the
    schema back as its answer.
- **Settings notice:** on OS 27, Smart Features recommends GPT-6 Luna for accuracy and
  cost, and tells users to review results before creating a category with any model.
  On OS 26, where only Apple Intelligence is available, it shows only the review
  advice.

## Follow-up: custom models and Bailian's DeepSeek

On 2026-11-20 the maintainer asked for the two providers to match the others:

- **Custom models:** every cloud provider accepts a custom model ID, through the
  same Custom Model… prompt and warning. `AIBackend.allowsCustomModel` is gone; the
  check is `isProvider`.
- **Bailian suggestions:** `qwen3.8-flash` (default, "Qwen 3.8 Flash") and
  `deepseek-v4.1-flash` ("DeepSeek V4.1 Flash"), the Bailian route from the table
  above. The DeepSeek-through-Bailian route, previously left out, is now offered.
- **DeepSeek suggestions:** `deepseek-flash` only, unchanged.

The custom-model risk notice and the JSON-object wire format apply to these models
too. Neither was re-measured for a custom ID, so the notice still says AniShelf did
not check the model.

## Refs

- `MyAnimeList/Sources/AI/AIConfiguration.swift`
- `MyAnimeList/Sources/AI/AIStructuredGenerator.swift`
- `MyAnimeList/Sources/AI/Vendor/ChatCompletionsLanguageModel.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSmartFeaturesSettings.swift`
- `MyAnimeList/Tests/MyAnimeListTests/AIFoundationTests.swift`,
  `SmartFeaturesTests.swift`: provider request bodies and fixed-model settings.
- `PRIVACY_POLICY.md`, `docs/anishelf_overview.en.md`, `docs/anishelf_overview.md`

## Validation

- `make build-mac`: passed.
- `AIFoundationTests` and `SmartFeaturesTests` on macOS: 28 tests passed.
- **Live check:** a local Swift probe (not retained) ran the production adapter
  against both live endpoints with synthetic cards, and got a valid connection check,
  plan, and selection from each. No library data was sent.
- **Not checked:** the Settings layout on any platform, the iOS simulator, and the
  full Describe a Category flow in the app with either new provider.
