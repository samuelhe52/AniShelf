# 020 — Native macOS app: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-15 | Feasibility assessment saved | `7f26492` |
| 2026-10-15 | Implementation approved; decisions and slices recorded ([002](002-implementation-decisions.md)) | `040e44d` |
| 2026-10-15 | Slice 1: native build and launch ([003](003-slice-1-native-build.md)) | `93efb7f` |
| 2026-10-16 | Slice 2: Mac shell ([004](004-slice-2-mac-shell.md)) | `533206a` |
| 2026-10-16 | Slice 3: feature parity ([005](005-slice-3-feature-parity.md)) | `ff73ed0` |
| 2026-10-16 | Slice 4: polish, validation, and final review fixes ([006](006-slice-4-polish.md)) | `dc6f46b` |
| 2026-10-16 | Platform boundary refactor ([007](007-platform-boundary-refactor.md)) | `71ab52f` |
| 2026-10-16 | System window sizing: removed the inspector width correction, sidebar auto-collapse, and inspector-open column minimum ([010](010-system-window-sizing.md)) | "refactor: Let AppKit size the Mac window when the inspector opens" |

Work is on `feat/native-macos`; it is not pushed or merged. `main` was not
changed.

## Outcome and current state (as of 2026-10-16)

The `MyAnimeList` target builds natively for macOS 26 as well as iOS, with
Catalyst off. It keeps the same bundle identifier, iCloud container, and
sandboxed UUID data container as the iPad-on-Mac build. The Mac app has:

- A sidebar split view with the library in the content column and entry detail
  in the trailing inspector.
- Desktop click, ⌘-click, ⇧-click, and keyboard selection.
- Menu-bar commands and a Settings window.
- Multiple windows and tabs.
- Save panels for exports and posters.
- An `NSApplicationDelegate` for CloudKit pushes, reminder notifications,
  periodic reminder refresh, and quit/sleep sync.

iOS behavior is unchanged except where the slice records say so: none
intentionally.

Key source paths:

- `MyAnimeList/Sources/Mac/`: lifecycle, sidebar, commands, Settings root.
- `MyAnimeList/Sources/Mac/LibraryView+Mac.swift`: the split view, the selection
  state machine, and the split view's column widths. These lived in
  `LibraryView+Desktop.swift` until [007](007-platform-boundary-refactor.md).
- `MyAnimeList/Sources/Utils/PlatformViewModifiers.swift` and
  `PlatformImage.swift`: platform shims.
- `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift`: sharing and save
  panels.
- `MyAnimeList.xcodeproj/project.pbxproj`, `MyAnimeList/MyAnimeList-macOS.entitlements`,
  `Makefile` (`build-mac`, `test-app-mac`, `test-mac`, `run-mac`).

## Validation against the plan's criteria

1. **Native build:** `make build-mac` and `make build` pass. The actual compiler
   blockers were few. SHContainers was removed because it was unused and
   UIKit-only. The rest were handled with small shims; see 003.
2. **Feature exercise:** every listed area was exercised through computer use
   against snapshot builds (rounds `s1`–`s4d`, reports in the untracked
   `.build/mac-review/`). Purchases went only as far as loading prices.
3. **Desktop behavior:** keyboard focus, menus, ⇧/⌘ selection, resizing, sheets,
   multiple windows and tabs, last-window close and reopen, and quit were
   checked manually. Sleep/wake and the quit-time flush timeout were reviewed in
   code but not run.
4. **Sync and notifications:** with the maintainer's permission, iCloud Sync ran
   against the CloudKit development environment. It synced an edit
   automatically, and APNs registered. Firing and clicking an airing reminder
   and the 6-hour refresh were not exercised at runtime.
5. **Continuity:** the native build opened the existing sandboxed container
   (137 entries) and the TMDb key without prompts. It was not validated as an
   upgrade from a distributed App Store build.
6. **Tests:** the iOS regression `make test-sim` (app and DataProvider) passed
   on the booted simulator. `MyAnimeListTests` now also runs natively with
   `make test-app-mac` and passed. Running it on the Mac exposed an SVG
   rasterization bug, now fixed.

## Deviations from plan

- 002 planned Codex as the main implementer with Claude Code reviewing. Partway
  through slice 1 the maintainer made Claude Code the implementer and kept one
  Codex session for UI inspection and code review.
- Settings is a sidebar window rather than the tabbed window 002 first planned
  (see 004).
- The library toolbar has no search field. Find in Library (⌘F) opens the
  existing search sheet in library mode, so that sheet keeps a single search
  implementation.

## Open questions

- Release distribution: signing, notarization or App Store submission, and the
  upgrade path from the iPad-on-Mac install are not set up or tested.
- Light-appearance contrast in the detail header and list badges (shared with
  iOS; see 006).
- A quick Done-then-reopen of the inspector once left a stale Done button; it
  was not reproduced (005).
- Reminder notification clicks, background refresh, sleep/wake, and the
  cross-volume overwrite path are verified only by code review.
