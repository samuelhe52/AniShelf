# 042.005 — Export speed, live preview, and pane wording

## Context
Samuel's first hands-on pass after slice 3 (2026-11-20): updating the snapshot was
"painfully slow", the preview only changed after an update finished, "publish" is not a
term users understand, and the pane had other quirks. Claude Code traced the causes in the
slice 2–3 code.

### Causes found
- `exportEntries` exports one image at a time.
- Posters use `.posterFull` (TMDb `original`, often 2000×3000) and backdrops use originals;
  the library itself shows w500 thumbnails, so Kingfisher rarely has these cached, and the
  exporter's `.cacheMemoryOnly` keeps nothing on disk for the next run.
- Images are encoded into a staging folder that is deleted when a run is cancelled. Every
  option change cancels the running export, so changes during an export restart it from
  zero.
- Every settings change waits the 5 s debounce and runs the full pipeline, even when only
  presentation (layout, titles, interval) changed.
- The preview reads the published folder, so it lags every change; it is hidden until the
  toggle is on, restarts and reshuffles on each new generation, and is fixed at 16:9.

## Decisions
| Choice | Reason and alternative |
| --- | --- |
| Setup steps instead of an on/off toggle | "Enable Screen Saver" only controlled the artwork folder. The pane shows: 1. **Install Screen Saver…** (also starts keeping artwork), 2. **Open Screen Saver Settings** and choose AniShelf. A small **Stop Updating and Remove Artwork** action undoes it. Rejected: a renamed toggle; always on. |
| Drop Refresh Now and Show in Finder | Updates are automatic; both exposed the mechanism. **Try Again** appears only after a failed update. |
| No "publish" wording | One status line in plain words, for example "Up to date · 48 posters" or "Preparing artwork… 12 of 48". |

## Change
- Presentation settings (layout, titles, interval) are written to the manifest at once,
  with no debounce and no image work. Only membership or artwork changes run the export,
  still debounced for library saves.
- Export writes directly into `images/` under request-identity names, so a cancelled run
  keeps finished files (unreferenced files are harmless and pruned after a commit), with
  about 4–6 concurrent images.
- Posters at the TMDb `w780` rendition; original backdrops only for Hero Still.
- A partial manifest is committed as images arrive, so the saver fills in progressively.
- The Settings preview renders from an in-memory source built from the current draft and
  images the app already has (Kingfisher), independent of the snapshot folder. It reacts
  to option changes immediately, works before setup, keeps one shuffle across updates,
  and uses the main screen's aspect ratio.
- The manifest carries a renderer version; an older installed saver shows an update notice.
- Other pane fixes: one status line in plain words ("Artwork updates start when you
  install the screen saver.", "Preparing artwork… 12 of 48", "Up to date · 48 posters",
  with " · N without artwork" only above zero), no timestamps, readable errors with Try
  Again, "Show" instead of "Library Scope", and a `ContentUnavailableView` when the
  library is not ready.

### As built
- Export: six concurrent workers; posters use the new `TMDbImageVariant.screenSaverPoster`
  (TMDb `w780`, 1500 px); the first ready artwork commits at once and later partial
  manifests are batched about every 150 ms; an entry keeps its current poster while a
  replacement loads.
- Compatibility: manifest schema 2 plus `rendererVersion` 2. Schema 1 savers, which did
  not check a renderer version, see the update notice; later renderer-only changes bump
  `rendererVersion`. The saver bundle build number is now 2.
- Preview: `ScreenSaverRenderer.updatePreview` plays an in-memory sample of up to 24
  entries from the library's own Kingfisher variants (`posterThumbnail`, `backdrop`),
  ranked by a per-view seed so scope changes keep the order of surviving entries.
- Setup: Install Screen Saver… turns artwork updates on when macOS accepts the open;
  Open Screen Saver Settings goes to the Wallpaper pane, where macOS 27 keeps screen
  savers (no separate Screen Saver pane exists on this system).
- Note: the catalog key "Show" is generic and its `ja` value (表示する作品) fits only this
  picker; reuse of `Text("Show")` elsewhere would inherit it.

## Refs
- Implemented by a new Codex session (`gpt-6.2-sol`, high), with one review round on the
  status wording; visual checks stayed inside AniShelf and in-process renders (no system
  screen saver activation).
- Fixture timings by Codex (48 posters, 36 backdrops, generated local artwork, so no TMDb
  latency): cold Hero Still export 4.42 s → 1.36 s; interval change to committed
  manifest 5.10 s → 9.5 ms. Real-library gains from `w780` and concurrency are not yet
  measured.
- Validation by Codex: focused publisher and ScreenSaverKit tests, `make build-mac`,
  `make build`, `codesign --verify --strict` on the embedded saver, `make run-mac` with a
  48-entry fixture including Stop Updating and Remove Artwork.
- Re-run by Claude Code: `swift test --package-path ScreenSaverKit` (10 passed);
  `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'` (passed); `make build` (passed).
