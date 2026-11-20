# Describe a Category evaluation

`scripts/category_eval.py` reruns the Describe a Category benchmark against cloud
providers. It needs Python 3 and nothing else. Run it from the repository root.

## Running it

```sh
# Offline: check the dataset and labels, and dry-run batch packing. No network.
python3 scripts/category_eval.py

# Live: load the keys, smoke one request on every route, then run the full comparison.
set -a; . "$HOME/.secrets/env/ai-tokens.env"; set +a
python3 scripts/category_eval.py --live --case 5 --rounds 1 --max-calls 80
python3 scripts/category_eval.py --live --max-calls 1200

# Runner unit tests.
python3 -m unittest discover -s scripts/tests
```

| `--model` | Route | Key variable |
| --- | --- | --- |
| `luna` | OpenRouter `openai/gpt-6-luna` | `OPENROUTER_OPENCLAW_API_KEY` |
| `qwen` | Bailian `qwen3.8-flash` | `BAILIAN_API_KEY` |
| `bailian-flash` | Bailian `deepseek-v4.1-flash` | `BAILIAN_API_KEY` |
| `deepseek-flash` | DeepSeek `deepseek-flash` | `DEEPSEEK_API_KEY` |

- Repeat `--model` to pick several routes; the default is all four.
- `--case N` picks a request by its number in the offline listing, and can repeat.
- `--rounds` is 1 or 2 (default 2). Agreement needs two rounds.
- `--live` requires `--max-calls`. A full four-route run takes about 1,030 calls.
- The offline check also rejects entries missing a field the live filters read.

## Private data

The data lives in `~/Library/Application Support/AniShelf Category Eval/`, outside
Git, because it records the maintainer's library. Keep a private backup.

- `benchmark-reviewed-borderlines.json` is the default input: the reconstructed
  library with the maintainer's 30 label corrections (SHA-256 `fc253cda…`).
- `benchmark.json` has the uncorrected labels (SHA-256 `6da7d367…`). Pass it, or a
  restored copy, with `--data`.
- Live runs send the request text and each entry's public card (title, year, kind,
  studios, genres, overview start) to the selected providers. Watch status, score,
  favorites, finish year, labels, and media IDs stay local.

## Results

Each live run writes a new `run-<timestamp>/` directory beside the input, holding:
- `manifest.json`: dataset and runner hashes and the configuration;
- one JSON file per route, case, and round: the plan, each batch request and
  response, usage when reported, decisions, and timing;
- `scores.json`: scores per case and per route.

There is no response cache and no retry. A failed plan or batch, including a
truncated response body, leaves its entries unchecked, not rejected. A case with
unchecked entries gets no quality scores, and its route gets no macro scores; the
script then exits nonzero.

Compare macro precision and recall, which exclude borderline labels, and agreement
between rounds. Precision is 0 when a case has labeled matches and no predicted ones,
and undefined when it has neither; recall is undefined without labeled matches.
`scored_cases` counts the cases where each metric is defined. Read the saved plans by
hand for filter accuracy, the criterion, and the language of the name.

## What the runner tests

The runner is a Python port of the planner prompt, the local filters, and the indexed
check batches, with the app's 4,096-token context budget, 512-token output cap, and
reasoning off. Every route gets the same batches, as in the app. Luna uses a strict
JSON schema; the other routes use JSON-object mode with an example shape and local
validation, like the app.

It does not test the app's streaming client, the UI, or the exact app prompts: the
prompt text is copied by hand from `CategoryQueryPlan.swift` and
`AIBatchRunner.swift`, and the JSON-object instruction is worded differently from
`AISessionFactory`'s. When those prompts change, update the copies before comparing
with older runs. Always compare routes within one run, or against a fresh Luna run,
rather than with numbers from another dataset.

## Reconstruction (November 2026)

The October evaluation ([004](004-settings-and-described-categories.md#current-state))
ran inside the macOS app test host on a copy of the library store. Its inputs and
per-call results were lost; its scores are historical, not a baseline.

`benchmark.json` was rebuilt from session transcripts (Codex thread
`01a1838d-9700-7802-b363-e65f70bf1fd3`; Claude Code sessions
`88bde857-ddf0-481e-9e67-379344caa849` and `40571c45-8ea5-4541-8c52-31b0f7c0fcb1`)
and a local library backup:
- The archived roster fixed the 135 entries and their order. Every entry matched the
  backup by title, kind, and air year, and the first two studios and genre IDs agreed
  for all 135. All 20 full cards printed in the transcripts matched exactly.
- The original labeling rules reproduce 1,080 judgments over eight requests, with the
  original outcome counts.
- Entry IDs are new, so the file is not a byte-for-byte copy of the original.

`history-2026-10-29/`, beside the data, keeps the recovered source snippets and
transcript excerpts for reference.

When the runner was rebuilt, the offline check covered all 1,080 labels and packed
the 135 entries into 16 batches per route. A live smoke run with two fictional cards
returned a valid plan and the expected selection on every route, and a run that hit
the call cap correctly withheld its scores.
