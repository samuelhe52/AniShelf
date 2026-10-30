# 034.003 — Reasoning off by default

## Context

The vendored adapter sent no reasoning setting, so providers used their own default
reasoning. On OpenAI that counts against `max_completion_tokens`, and the foundation
slice compensated by reserving 2048 response tokens, which halved the input left for
entries under the shared 4096 cap.

On 2026-10-28 the maintainer named the likely UI options and asked for them to be
checked with plain curl requests:
- `gpt-6-luna` through OpenAI and OpenRouter;
- `anthropic/claude-haiku-5.5`;
- `deepseek/deepseek-v4.1-flash`.

All were run with reasoning low and with reasoning off. The request was a strict
`json_schema` selection over six cards, one with a Chinese overview, with a 512-token
cap. Through the maintainer's proxy, all eight combinations returned the expected
indices. With reasoning off each needed about 20 completion tokens and 0 reasoning
tokens. DeepSeek's "low" still used 149 reasoning tokens.

Without the proxy, from mainland China:
- `api.openai.com` never connected.
- `openrouter.ai` connected only intermittently, and when it did, returned 403 "not
  available in your region" for the OpenAI and Anthropic models.

The maintainer deferred mainland reachability in favor of waiting for Apple
Intelligence there.

## Change

- **Adapter:** the vendored adapter gains an optional `Reasoning` setting. It is
  encoded either as OpenAI's top-level `reasoning_effort` or as OpenRouter's
  `reasoning` object, and `nil` sends nothing. The file header records the
  modification.
- **App setting:** `AIReasoning` (`off`, `low`, `medium`, `high`), off by default.
  `AISessionFactory.reasoning` maps it per backend:
  - OpenAI: `reasoning_effort: "none"`, or the level;
  - OpenRouter: `reasoning: {enabled: false}`, or `{enabled: true, effort: <level>}`;
  - the Apple system model ignores it.
- **Budget:** `AIContextBudget.make` takes the same setting and reserves 512 response
  tokens with reasoning off and 2048 with it on, replacing the OpenAI-only 2048
  default.
- **Default models:** now `gpt-6-luna` (OpenAI) and `openai/gpt-6-luna` (OpenRouter).
  The previous defaults were never checked with `reasoning_effort: "none"`.

## Refs

- `MyAnimeList/Sources/AI/Vendor/ChatCompletionsLanguageModel.swift`
- `MyAnimeList/Sources/AI/AIConfiguration.swift`
- `MyAnimeList/Sources/AI/AIStructuredGenerator.swift`
- `MyAnimeList/Sources/AI/AIContextBudget.swift`
- `MyAnimeList/Tests/MyAnimeListTests/AIFoundationTests.swift`: the
  `reasoningIsOffByDefaultOnTheWire` test checks each backend's request body through a
  mock `URLProtocol`.

## Validation

- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/AIFoundationTests'` on the
  booted iOS 27.2 simulator: passed, including both arguments of the new wire test.
- `make build-mac`: passed.
- **In-app check:** the DEBUG provider check (`ANISHELF_AI_SMOKE_TEST`) on the
  simulator passed for `gpt-6-luna` through OpenAI and `openai/gpt-6-luna` through
  OpenRouter. The simulator still reports a context size of 0, so the 4096 fallback
  applied. The check did not inspect reasoning token usage; that comes from the curl
  checks above.
- **Not checked:** Haiku and DeepSeek in the app (curl only), and any reasoning level
  other than off in the app.
