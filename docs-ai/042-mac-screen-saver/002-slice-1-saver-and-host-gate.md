# 042.002 — Slice 1: ScreenSaverKit, saver target, host-access gate

## Context
First implementation slice of [000-plan.md](000-plan.md), done by a Codex session
(`gpt-6.2-sol`, high effort) and reviewed by Claude Code. The slice had to prove the
snapshot handoff before any app-side publishing was built.

## Change
- `ScreenSaverKit/` (local package, macOS 26): `ScreenSaverManifest` (schema version 1,
  ISO 8601 second-precision dates), `ScreenSaverSnapshotReader` (version gate, empty and
  requires-update states, image references limited to files directly inside `images/`),
  `ScreenSaverRenderer` with a per-start session token and a background scene loader that
  prepares the next scene during the current one, and the three layouts (`CoverWall`,
  Poster Focus and Hero Still in `ScreenSaverLayouts`). Cover Wall rows fill the screen
  height (row count nearest to height / 260 pt, minimum 2); the wall drifts one column per
  12 s and recycles the leftmost column, avoiding a repeat of the horizontal or vertical
  neighbour when enough artwork exists; fewer than 4 readable posters fall back to Poster
  Focus. Entry order is shuffled per start with a seeded generator. Hero Still falls back per entry to Poster Focus without a backdrop.
- `ScreenSaver/AniShelfScreenSaverView.swift`: thin `ScreenSaverView` adapter. Ends the
  session on `stopAnimation`, on `com.apple.screensaver.willstop`, and on window
  detachment; reads `~/Pictures/AniShelf Screen Saver` through the login user's home.
  Own string catalog (`ja`, `zh-Hans`) for the two notices.
- `MyAnimeList.xcodeproj`: bundle target `AniShelfScreenSaver` (`AniShelf.saver`,
  `com.samuelhe.MyAnimeList.ScreenSaver`, arm64 + x86_64), embedded macOS-only in
  `Contents/Library/Screen Savers`; `ScreenSaverKit` linked macOS-only.

## Gate result
Passed on macOS 27.2.1 (Codex run, 2026-11-20): the installed saver read a fixture
snapshot from `~/Pictures/AniShelf Screen Saver` with no privacy prompt in the System
Settings preview, on direct `ScreenSaverEngine` activation, and on real idle activation
after 62 s. Lock Screen activation and activation after a restart are not yet checked.

## Refs
- Validation by Codex: `swift test --package-path ScreenSaverKit` (8 tests),
  `make build-mac`, `make build` (iOS app contains no `.saver`), `codesign --verify
  --strict` and `lipo` on the installed bundle, swift-format lint.
- Re-run by Claude Code: `swift test --package-path ScreenSaverKit`, 9 tests passed after the
  review corrections (fill height, shuffle, neighbour spreading) were folded in.
