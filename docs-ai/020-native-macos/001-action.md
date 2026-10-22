# 020 — Native macOS app: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-15 | Feasibility assessment, implementation decisions ([002](002-implementation-decisions.md)), and slice 1: native build and launch ([003](003-slice-1-native-build.md)) | `2e2c49c` |
| 2026-10-16 | Slice 2: Mac shell ([004](004-slice-2-mac-shell.md)) | `de8192b` |
| 2026-10-16 | Slice 3: feature parity ([005](005-slice-3-feature-parity.md)) | `54f1fc2` |
| 2026-10-16 | Slice 4: polish, validation, and final review fixes ([006](006-slice-4-polish.md)) | `9bfef61` |
| 2026-10-16 | Platform boundary refactor ([007](007-platform-boundary-refactor.md)) | `0d46027` |
| 2026-10-16 | Poster memory-cache start, on both platforms | `9be901a` |
| 2026-10-16 | Airing reminder notification handling shared across platforms | `35143f7` |
| 2026-10-16 | Mac-native UI, including system window sizing ([008](008-mac-native-ui.md)) | `3a71bb7` |
| 2026-10-17 | Mac selection and inspector model ([021](../021-mac-selection-model/000-plan.md)) | `5eef8c9` |
| 2026-10-17 | Mac About, Support, and What's New ([008](008-mac-native-ui.md)) | `f9b327e` |

Work is on `feat/native-macos`; it is not pushed or merged, and `main` was not
changed. On 2026-10-17 the branch history was rewritten from 36 commits into the
commits above. Fix chains and docs commits were folded into the work they
belonged to.

## Outcome and current state (as of 2026-10-17)

The `MyAnimeList` target builds natively for macOS 26 as well as iOS, with
Catalyst off. It keeps the bundle identifier, iCloud container, and sandboxed
UUID data container of the iPad-on-Mac build. The Mac app has:

- A sidebar split view: library scopes and categories in the sidebar, the
  library as a List or Grid, and a trailing inspector.
- A per-window selection (click, ⌘-click, ⇧-click, arrow keys). The inspector's
  visibility is a window setting, and its content follows the selection: no
  selection, one entry's detail, or a multi-item batch inspector ([021](../021-mac-selection-model/000-plan.md)).
- Inline Find in each window, and a TMDb-only Add sheet.
- Menu-bar commands, and a Settings window built from grouped forms.
- About and Support windows, and What's New in the Help menu.
- Multiple windows and tabs, and save panels for exports and posters.
- An `NSApplicationDelegate` for CloudKit pushes, reminder notifications,
  periodic reminder refresh, and quit/sleep sync.

iOS behavior is unchanged, except for two changes that apply to both platforms:
the poster memory-cache start, and the shared airing-reminder handling.

Key source paths:

- `MyAnimeList/Sources/Mac/`: lifecycle, sidebar, commands, the selection model
  (`MacLibrarySelection.swift`), the inspector (`MacLibraryInspector.swift`,
  `MacBatchSelectionPanel.swift`), Settings, and the app-info views.
- `MyAnimeList/Sources/Mac/LibraryView+Mac.swift`: the split view, column widths,
  and the Mac entry actions.
- `MyAnimeList/Sources/Utils/PlatformViewModifiers.swift` and
  `PlatformImage.swift`: platform shims.
- `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift`: sharing and save panels.
- `MyAnimeList.xcodeproj/project.pbxproj`, `MyAnimeList/MyAnimeList-macOS.entitlements`,
  `Makefile` (`build-mac`, `test-app-mac`, `test-mac`, `run-mac`).

## Validation against the plan's criteria

1. **Native build:** `make build-mac` and `make build` pass for every commit in
   the rewritten history. The compiler blockers were few: SHContainers was
   removed because it was unused and UIKit-only, and the rest were handled with
   small shims (003).
2. **Feature exercise:** every listed area was exercised through computer use
   against snapshot builds in slices 1–4 (rounds `s1`–`s4d`; screenshots and
   reports were local and not retained). Purchases went only as far as loading
   prices.
3. **Desktop behavior:** keyboard focus, menus, ⇧/⌘ selection, resizing, sheets,
   multiple windows and tabs, last-window close and reopen, and quit were
   checked manually during the slices. The selection model and app-info windows
   of 021 and 008 have not been checked at runtime yet. Sleep/wake and the
   quit-time flush timeout were reviewed in code but not run.
4. **Sync and notifications:** with the maintainer's permission, iCloud Sync ran
   against the CloudKit development environment. It synced an edit
   automatically, and APNs registered. Firing and clicking an airing reminder,
   and the 6-hour refresh, were not exercised at runtime.
5. **Continuity:** the native build opened the existing sandboxed container
   (137 entries) and the TMDb key without prompts. It was not validated as an
   upgrade from a distributed App Store build.
6. **Tests:** `make test-sim` (app and DataProvider) passed on the booted
   simulator during slice 4. `MyAnimeListTests` also runs natively with
   `make test-app-mac`. Running it on the Mac exposed an SVG rasterization bug,
   now fixed (005). Later focused runs are listed in 008 and 021.

## Deviations from plan

- 002 planned Codex as the main implementer with Claude Code reviewing. Partway
  through slice 1 the maintainer made Claude Code the implementer and kept one
  Codex session for UI inspection and code review.
- Settings is a sidebar window rather than the tabbed window 002 first planned
  (004).
- 002's Mac selection reused the iOS presentation and multi-select state. That
  model produced repeated ordering bugs, and 021 replaced it with a Mac-only
  selection.
- The Mac has no Gallery view (008).

## Open questions

- The local production export path was implemented and launch-tested on
  2026-10-18 ([009](009-local-production-export.md)). Public distribution,
  notarization, App Store submission, and the distributed upgrade path remain
  outside that validation.
- The grid's reflow jitter while the inspector animates (008, 021).
- Light-appearance contrast in the detail header and list badges, shared with
  iOS (006).
- Reminder notification clicks, background refresh, sleep/wake, and the
  cross-volume overwrite path are verified only by code review.
