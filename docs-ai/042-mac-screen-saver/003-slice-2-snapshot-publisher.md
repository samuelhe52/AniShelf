# 042.003 — Slice 2: Snapshot builder and publisher

## Context
Second implementation slice of [000-plan.md](000-plan.md): the app side that turns the
library into a published snapshot. Implemented by the Codex session, reviewed by Claude
Code; one review round of six corrections was applied before commit.

## Change
- `MyAnimeList/Sources/Mac/ScreenSaver/ScreenSaverSettings.swift`: Mac-local options in
  `UserDefaults` (`screenSaverEnabled`, `screenSaverScope`, `screenSaverLayout`,
  `screenSaverShowsTitles`, `screenSaverInterval`), not cloud-synced. Defaults: off,
  Favorites, Cover Wall, titles on, 12 s.
- `ScreenSaverSnapshotBuilder.swift`: builds a draft from `LibraryStore.library`, filtered
  by scope without widening, ordered by identity (the saver shuffles per session). Titles
  via `displayName`, season labels via `EntryDetailViewModel.seasonLabelText(_:locale:)`
  (new `locale` parameter) in the resolved Anime Info Language; Hero Still meta line from
  year, up to three localized genres, and series status. Titles, season labels, and logos
  are omitted when titles are off.
- `ScreenSaverImageExporter.swift`: Kingfisher retrieval with memory-only caching for the
  processed result, so the exporter adds no disk-cache keys outside
  `LibraryImageCacheService.relatedCacheKeys`. Posters at `.posterFull`, backdrops from the
  original rendition downscaled to 2560 px, logos as PNG. Files are named by a hash of the
  request identity and reused when present, so unchanged art is never re-encoded.
- `ScreenSaverPublisher.swift` and `ScreenSaverSnapshotWriter.swift`: one publisher per app
  process, owned by `LibraryStore` and started from `MyAnimeListApp` (also after startup
  recovery; fixture launches only when the saver is enabled in their defaults). Refreshes
  on launch, library saves (including saves that do not change membership), and
  preference or locale changes, debounced 5 s; unchanged drafts do nothing. A smaller
  scope or deletion publishes the reduced manifest before new images are fetched.
  Disabling replaces an existing manifest with an empty one; a fresh disabled launch
  leaves Pictures untouched. Only a failed poster drops an entry; a failed backdrop or
  logo keeps it (Poster Focus or title-text fallback). Writes new images, then the
  manifest atomically, then prunes files referenced by neither the current nor the
  previous manifest.
- `MyAnimeList/MyAnimeList-macOS.entitlements`: `com.apple.security.assets.pictures.read-write`.

## Refs
- Tests: `MyAnimeList/Tests/MyAnimeListTests/ScreenSaverPublisherTests.swift` (8 tests).
- Validation by Codex: `make test-app-mac` for the publisher tests and the library save
  invalidation suite, `make build`, `make build-mac`, universal macOS build, and three
  `make run-mac` fixture launches that published 24 entries (18 backdrops) and rendered
  each layout in the installed saver; layout changes reused all 24 poster files.
- Re-run by Claude Code: `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests'`,
  8 tests passed.
