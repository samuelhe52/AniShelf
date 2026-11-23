# 042.004 — Slice 3: Settings pane, preview, and install

## Context
Third implementation slice of [000-plan.md](000-plan.md): the user-facing Mac Settings
pane. Implemented by the Codex session and reviewed by Claude Code.

## Change
- `LibraryProfileSettingsDestination.screenSaver` exists only in macOS builds (the case is
  compiled out elsewhere), placed after Appearance & Interaction, with the `display`
  symbol and a muted purple tint.
- `MyAnimeList/Sources/Mac/ScreenSaver/MacScreenSaverSettingsPage.swift`: Enable Screen
  Saver, Library Scope with the eligible count (same filter as publication,
  `ScreenSaverSettings.Scope.includes`), Layout, Show Titles, and Interval (5, 8, 12, 20,
  30, 60 s, keeping a saved custom value; shown for Poster Focus and Hero Still only).
  The options write through `ScreenSaverPublisher.settings`. A Publication section shows
  the last publication time, entries without artwork, and errors, with Refresh Now, Show
  in Finder, and Install Screen Saver…, which opens the embedded `AniShelf.saver` so macOS
  shows its own install or replace prompt.
- `ScreenSaverPreviewView.swift`: `NSViewRepresentable` hosting `ScreenSaverRenderer`;
  restarts when a new manifest generation is published.
- Fixture launches start the publisher but leave an existing snapshot untouched until the
  saver is enabled in the fixture's defaults.
- `LibraryProfileSettingsPages.swift`: the shared Mac settings `Form` now applies
  `preferredNavigationBarScrollEdgeEffect()`, per the project convention; this affects
  every Mac settings page.
- Cover Wall repeat avoidance now compares poster paths instead of hashing decoded
  pixels (exported files are already named by request identity).
- 25 new strings in `MyAnimeList/Resources/Localizable.xcstrings` with `ja` and `zh-Hans`.

## Refs
- Validation by Codex: `make run-mac MAC_LAUNCH_ARGS='-library-fixture 48'` drove the pane
  end to end (6 Favorites, 22 Watched, Poster Focus and Hero Still previews, Refresh Now,
  Show in Finder, the system replace prompt captured and cancelled, disable published an
  empty manifest); `make build`; `swift test --package-path ScreenSaverKit` (9 tests);
  publisher and Settings layout tests via `make test-app-mac`.
- Re-run by Claude Code: `swift test --package-path ScreenSaverKit` (9 passed);
  `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'` (passed).
