# 042 — Mac screen saver: Plan

| Field | Value |
| --- | --- |
| Status | In progress |
| Anchor date | 2026-11-20 |
| Origin | Outside contributor proposal, [PR #28](https://github.com/samuelhe52/AniShelf/pull/28) (davidch81-tech, heads `e20c161` to `c6c267f`). Samuel decided to build the feature natively from scratch, taking ideas and designs only. Investigated by Claude Code and an independent Codex session; decisions answered on an HTML plan on 2026-11-20. |
| Related | [020-native-macos](../020-native-macos/000-plan.md), [036-image-variant-catalog](../036-image-variant-catalog/000-plan.md), [039-library-save-invalidation](../039-library-save-invalidation/000-plan.md), [016-settings-hub](../016-settings-hub/000-plan.md), [backlog.md](backlog.md) |

## Background

PR #28 adds a standalone Objective-C `.saver` plus a Python exporter that copies
`mal.store` and reads SwiftData's private Z-tables with SQLite, then downloads TMDb art
into the saver bundle. The idea (a poster wall of your own library as the Mac screen
saver) is worth building. The implementation is not: it couples to the private store
format (`ZGENREIDS` is even decoded as a keyed archive), ignores custom posters (20 of
146 entries in Samuel's library), misreads season titles outside Chinese, maps original
language to country, widens small scopes to the whole library, leaks scene work across
rebuilds, has no `willstop` handling, and installs with scripts and a personal bundle ID.
The full findings are in the PR review discussion; the ones that shape this design are
listed under **Pitfalls to avoid**.

Platform facts that constrain the design (verified on macOS 27.2.1 / SDK 27.2 unless
marked):

- The only public API is `ScreenSaverView` (`ScreenSaver.framework`). Xcode ships a
  Screen Saver *project* template, no target template.
- Savers load in-process into Apple's `legacyScreenSaver` host. A plug-in gets none of
  its own entitlements, so it cannot join an App Group. The host signature has App
  Sandbox, `assets.pictures.read-only`, a read-only absolute-path exception for `/`,
  user-selected read-only, app-scope bookmarks, and network client.
- The app is sandboxed with network client and user-selected read/write only
  (`MyAnimeList/MyAnimeList-macOS.entitlements`); it has no App Group.
- Unverified: whether reading `~/Pictures/AniShelf Screen Saver` from the host triggers
  any privacy prompt; whether App Review accepts an embedded `.saver` (guideline 2.4.5
  restricts installing code in shared locations); the exact behavior of reused host
  instances on macOS 26/27.

## Goals

- A Mac-only **Screen Saver** pane in AniShelf Settings to enable the saver, pick its
  content and layout, preview it live, see publication status, and install it.
- AniShelf publishes a snapshot (manifest + images) of the chosen entries to
  `~/Pictures/AniShelf Screen Saver`, automatically while it runs.
- An `AniShelf.saver` embedded in the app plays the snapshot offline in three layouts:
  Cover Wall, Poster Focus, Hero Still.
- The saver starts, stops, and recovers cleanly in the host, including when
  `stopAnimation` is not called.

### Non-goals

- No access to the store from outside the app; no Python or shell installers; no code
  from PR #28.
- No iOS/iPadOS surface; no schema change; no iCloud sync of saver options.
- No network access from the saver.
- The ideas cut from v1 are recorded in [backlog.md](backlog.md).

## Design / approach

### Components (all paths proposed)

| Part | Location | Role |
| --- | --- | --- |
| `ScreenSaverKit` | `ScreenSaverKit/` (local package beside `DataProvider/`, macOS 26) | `ScreenSaverManifest` (Codable), `ScreenSaverSnapshotReader`, `ScreenSaverRenderer` (CALayer scenes, one session per view), layouts. Links neither DataProvider nor Kingfisher. Unit tests. |
| Saver target | `ScreenSaver/` (bundle target `AniShelfScreenSaver`, product `AniShelf.saver`, bundle ID `com.samuelhe.MyAnimeList.ScreenSaver`, principal class `AniShelfScreenSaverView`) | Thin `ScreenSaverView` adapter; own small string catalog for the empty and update states. arm64 + x86_64, macOS 26. |
| App side | `MyAnimeList/Sources/Mac/ScreenSaver/` | `ScreenSaverSettings`, `ScreenSaverSnapshotBuilder`, `ScreenSaverImageExporter`, `ScreenSaverPublisher`, `MacScreenSaverSettingsPage`, `ScreenSaverPreviewView`. |

The app target embeds `AniShelf.saver` (macOS only) in `Contents/Library/Screen Savers`
and links `ScreenSaverKit` on macOS only, for the manifest type and the live preview.

### Snapshot

- Built on the main actor from `LibraryStore.library` (visible, one preferred row per
  identity), filtered by scope: Favorites, Watched (`watchStatus == .watched`), or All.
  A scope never widens; an empty scope publishes an empty manifest.
- Per entry: `LibraryEntryIdentity.rawID`; title from `displayName` plus a typed season
  label; poster from `selectedPosterPath` (custom poster wins); for Hero Still, the
  backdrop path, the logo path, year, up to three genres via
  `EntryDetailViewModel.localizedGenreNames`, and series status via
  `localizedStatus`, in `Language.resolvedAnimeInfoLanguage()`.
- No notes, scores, progress, watch status, synopsis, remote URLs, or SwiftData IDs.
- Manifest fields (sketch): `schemaVersion`, `generation: UUID`, `createdAt`,
  `settings { layout, showsTitles, interval }`, `entries [ { id, title?, subtitle?,
  meta?, poster, posterPixelSize, backdrop?, logo? } ]`.

### Images

- Retrieved through Kingfisher (cache first, then TMDb) like
  `SharingCardExportPipeline.loadImage`. Posters at the `.posterFull` rendition
  (1500 px long edge). Backdrops from the original rendition, downscaled to a 2560 px
  long edge. Logos rasterized to PNG (SVG logos go through the existing SVG processing).
- Written as content-addressed files (`images/<sha256>.heic`, logos `.png`). A failed
  image skips that entry for this publication and is counted for the status line.

### Publication

- Write new images first, then a staged manifest, then replace `manifest.json` in one
  step. Prune images referenced by neither the new nor the previous manifest.
- Automatic refresh while AniShelf runs: observe library saves and relevant
  preferences (saver settings, info language), debounce about 5 s, rebuild drafts, and
  write only when they differ from the last publication. Also after launch and backup
  restore. Deletions and scope reductions publish the smaller manifest before slow
  image fetches finish. **Refresh Now** forces a run. Disabling the saver publishes an
  empty manifest.
- One publisher per app process, not per window.

### Saver runtime

- States: idle → loading → playing / empty → stopped. Each `startAnimation` creates a
  session token; timers, decodes, and transitions from an older token do nothing.
- Ends the session on `stopAnimation`, on the `com.apple.screensaver.willstop`
  distributed notification, and on window detachment. Never calls `exit`.
- Reads the manifest at start and at each scene boundary (generation change reloads).
  A missing, unreadable, empty, or newer-version manifest shows a quiet localized
  message (set up in AniShelf / update the screen saver from AniShelf).
- Decodes off the main thread with bounded size; prepares the next scene before the
  transition.
- Layouts: Cover Wall (full rows only, poster height near 260 pt, columns derived from
  screen width, one slow horizontal drift that recycles off-screen tiles; fewer than 4
  entries falls back to Poster Focus); Poster Focus (whole poster, color wash derived
  from the poster, darkened toward the text side for light art, optional title,
  cross-fade at the chosen interval, stacked on portrait screens); Hero Still
  (full-screen backdrop, logo or title text, meta line; per-entry fallback to Poster
  Focus when there is no backdrop).

### Settings and install

- New `LibraryProfileSettingsDestination.screenSaver`, shown only on Mac. Options in
  `UserDefaults`, not in `cloudSyncedPreferenceKeys`: enabled (default off), scope
  (default Favorites), layout (default Cover Wall), show titles (default on), interval
  (default 12 s; Poster Focus and Hero Still).
- The pane shows the eligible count, the live preview (shared renderer), the last
  publication time, the count of entries without art, Show in Finder, and
  **Install Screen Saver…**, which opens the embedded bundle with `NSWorkspace` so macOS
  asks the user to install it.
- New strings go to `Localizable.xcstrings` with `ja` and `zh-Hans`. TMDb attribution
  stays in About.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Build in the app, not a script reading SQLite | SwiftData's on-disk schema has no compatibility contract and changes often; the app already resolves visibility, duplicates, custom posters, seasons, and language. |
| Snapshot in `~/Pictures/AniShelf Screen Saver` | The host already reads Pictures; the app needs only `com.apple.security.assets.pictures.read-write`. Rejected: a user-picked folder with a second bookmark in the saver (Codex's proposal; needs an Options sheet whose bookmark every host instance must reopen); an App Group (the host is not a member and current macOS protects other teams' group containers). Bonus: Apple's photo screen saver can show the same folder. |
| Default content: Favorites, with titles | Titles show nothing the posters do not. Rejected: titles off (most private), All Library. |
| Automatic refresh while running | The fixed folder needs no bookmark, so automatic refresh is cheap. Rejected: explicit Publish only. |
| Layouts: Cover Wall, Poster Focus, Hero Still | Samuel added Hero Still to the proposed two. Deck and Cover Fusion are deferred ([backlog.md](backlog.md)). |
| Embedded in the App Store app | One release pipeline keeps saver and manifest versions in step. Risk: App Review 2.4.5. Fallback: separate notarized download; the saver target and snapshot do not change. |
| Options only in AniShelf | One source of truth; System Settings Options sheets are unreliable on recent macOS. The saver has no Options sheet. |
| Shared `ScreenSaverKit` renderer | The Settings preview and the saver render identically; testable without the host. |

## Pitfalls to avoid (from PR #28)

- Do not widen a scope that has few entries.
- Do not let a delayed callback or decode from an old scene touch the current one.
- Do not rely on `stopAnimation` alone; do not kill the host.
- Do not hard-code a font for one script; use the system font so CJK text gets the right
  glyphs per language.
- Do not mark failed images as present in the manifest; do not rewrite the manifest in
  place.
- Do not crop text into negative widths on portrait displays; test 16:10, 16:9,
  ultrawide, and portrait.

## Validation and acceptance criteria

- Slice 1 gate (host access): a built `AniShelf.saver`, installed in
  `~/Library/Screen Savers`, reads a fixture snapshot from `~/Pictures/AniShelf Screen
  Saver` with no privacy prompt in the System Settings preview and on idle activation.
  Samuel checks lock screen and after-restart behavior. If this fails, stop and revisit
  the handoff decision.
- `ScreenSaverKit` unit tests: manifest round trip and version gate, reader fallbacks,
  Cover Wall grid math across aspect ratios, session invalidation.
- App unit tests (`make test-app-mac APP_TEST_ONLY=...`) with `LibraryFixture`: scope
  filtering including zero and one match, hidden parents, duplicates, custom posters,
  season titles, language, publication atomicity and pruning, refresh debounce and
  no-op on unchanged drafts.
- `make build-mac` and `make build` (iOS must still build without the saver).
- Behavioral run with `make run-mac` (fixture library): publish, install, preview, and
  activation of each layout; repeated activation and dismissal with stable memory and
  CPU; display changes.
- Visual pass by Samuel.

## Amendments
- Updated 2026-11-20: slice 1 landed and the host-access gate passed — see [002-slice-1-saver-and-host-gate.md](002-slice-1-saver-and-host-gate.md)
- Updated 2026-11-20: slice 2 landed (snapshot builder, image export, publisher) — see [003-slice-2-snapshot-publisher.md](003-slice-2-snapshot-publisher.md)
- Updated 2026-11-20: slice 3 landed (Settings pane, preview, install) — see [004-slice-3-settings-pane.md](004-slice-3-settings-pane.md)
- Updated 2026-11-20: setup steps replace the enable toggle, publish wording and Refresh Now / Show in Finder go, export and preview reworked for speed — see [005-export-speed-and-pane-revision.md](005-export-speed-and-pane-revision.md)
- Updated 2026-11-20: true-scale preview, Cover Wall rows, per-layout detail toggles, Poster Focus and Hero Still redesigned — see [006-preview-rows-and-details.md](006-preview-rows-and-details.md)
- Updated 2026-11-20: Uninstall via Finder, System Settings thumbnail, title always on, overview / TMDb score / watch status details — see [007-uninstall-thumbnail-and-more-details.md](007-uninstall-thumbnail-and-more-details.md)
- Updated 2026-11-20: slide typography reworked, text drawn with CoreText — see [008-slide-typography.md](008-slide-typography.md)
- Updated 2026-11-20: custom categories as a scope — see [009-category-scope.md](009-category-scope.md)
