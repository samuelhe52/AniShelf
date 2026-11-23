# 043 — AniShelf Lab on macOS: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-11-21 |
| Origin | Samuel wanted to test on the Mac with his real library, isolated from it; the synthetic fixture library misses real-world cases. Planned with Codex, reviewed by an Opus 5.5 agent, then cut down to a minimally invasive version by Claude Code. |
| Related | [020-native-macos](../020-native-macos/000-plan.md), [026-library-performance-benchmarks](../026-library-performance-benchmarks/000-plan.md) |

## Goals

- **AniShelf Lab**: a second Mac app (`com.samuelhe.MyAnimeList.lab`) that runs on a
  throwaway copy of the live library and preferences.
- `make run-lab` takes a fresh copy and opens Lab on it, every time. Nothing a Lab run
  changes survives to the next one. `LAB_LANG=ja` overrides the UI language.
- `make export-mac-defaults OUT=…` exports the live app's full preferences.

### Non-goals

Live AniShelf knows nothing about Lab, and Lab should cost production code as little
as possible. Lab never syncs and never reads the live app's Keychain items.

## Design / approach

Lab is the ordinary Debug Mac build, given another bundle ID, display name, and
entitlements (`MyAnimeList/AniShelfLab-macOS.entitlements`: sandbox, network, no
iCloud, push, or Pictures) plus the `ANISHELF_LAB` flag, all on the `xcodebuild`
command line in the Makefile.

Neither sandbox can see the other, so `scripts/lab.py` copies the live store through a
read-only SQLite connection (consistent even while AniShelf is open) and the live
preferences into Lab's `tmp/AniShelfLab/Snapshot`, then opens Lab.

At launch (`MyAnimeList/Sources/App/LabStartup.swift`), Lab deletes its Application
Support folder, its preferences, and the previous run's copy. It then moves the
snapshot into place, applies the backup's preference keys (`String.allPreferenceKeys`),
and opens it like a fixture launch (docs-ai 026), so sync, reminders, the review
prompt, and What's New stay off through existing code. Launched without a fresh
snapshot, it shows an error instead.

Production code knows about Lab in three places: that startup hook, the TMDb Keychain
account, and the bundle ID that names the AI provider Keychain items.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Throwaway file copy | SwiftData cannot load a file into an in-memory store; copying entries into one would need a copier that tracks every schema change. |
| Copy on every launch | No state to manage across runs. Rejected: a persistent working copy with an explicit refresh command. |
| Host-side copy | Keeps the live app unaware of Lab. Rejected: a "Refresh Lab" action in live AniShelf. |
| Reuse fixture mode | Its gates already turn off everything that acts outside the app. Rejected: per-service `#if ANISHELF_LAB` branches in about 30 files. |
| Command-line build settings | No Xcode configuration, scheme, or project changes to drift. Rejected: a `Lab` configuration on every target. |
| Lab-only TMDb key | Kept across runs; see [002](002-lab-tmdb-keychain.md). |

## Validation and acceptance criteria

Never use the live store for testing without Samuel's permission; the copy itself only
reads it.

## Amendments

- Updated 2026-11-21: Replaced the per-launch TMDb key with a Lab-only Keychain item — see [002-lab-tmdb-keychain.md](002-lab-tmdb-keychain.md).
