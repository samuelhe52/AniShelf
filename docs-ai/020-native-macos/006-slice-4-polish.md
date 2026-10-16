# 020.006 — Slice 4: polish and validation

## Context

Last slice of [002-implementation-decisions.md](002-implementation-decisions.md):
keyboard and focus, windows and tabs, resizing, light and dark appearance,
localization, the app icon, and the full regression runs. Roles are the same as
in slices 2 and 3. Every computer-use round (`s4a`–`s4d`) ran against a copied
snapshot build outside the source tree and left the library at 137 entries.

## Change

| Area | Mac behavior and reason |
| --- | --- |
| Grid keyboard | The grid scroll view takes focus on click. ←/→ move the inspected entry by one card and ↑/↓ by one row. The row length is computed from the measured width with the same rule as the adaptive `GridItem`. Moves go through the click path (`click(id, .replace)`), so a later ⇧-click extends from the keyboard position. Escape clears the selection. List and Gallery already had arrow keys; the grid, the default Mac view, did not. |
| Scope and inspector | A sidebar or filter change that hides the inspected entry closes the inspector (`dismissInspectorOutsideScope`), as a Finder selection does not survive changing folders. Only scope changes trigger it: changing the entry's own status in the inspector leaves it open even when the entry leaves the current scope. A batch selection already dropped hidden entries through the multi-select snapshot. Found when a scope change in one tab left the other tab inspecting an out-of-scope entry. |
| Toolbar browse menu | On the Mac, the sort/group/filter capsule shows only its glyphs. AppKit sizes a toolbar item once, so a label that grew from "All" to "Watching" collapsed to "…". The scope is already the window title. Combined filters, which match no sidebar row, now title the window "N Filters" instead of "Library". |
| Picker labels | Segmented pickers that sit under their own heading hide their label (sharing Language and Export Size, reminder timing, anime info language). macOS draws a picker's label beside the control; iOS never did for segmented pickers, so iOS is unchanged. |
| App icon | The `AppIcon` set gains the ten macOS sizes, generated from the iOS artwork in the macOS icon template: an 824pt continuous-corner squircle centered on a 1024pt canvas with a soft shadow. macOS does not mask a full-bleed square as iOS does. The build now emits `AppIcon.icns`. |

### Fixes from the final review

Sol reviewed the whole branch against `main` (static review; no P1 and no iOS
regression found). These fixes were folded into the slice commits they correct:

- Mac menu commands act only on the inspected entry. Before, they fell back to
  the last focused entry, even after it had been deselected or had left the
  scope. Show Inspector still reopens that entry while it is shown. iOS keeps
  its fallback.
- A reminder click targets the frontmost library window, restoring it if
  minimized, or opens a new one when all are closed (`MacLibraryWindows`).
  Before, whichever window observed the route first claimed it, and nothing
  opened a window.
- Any single selection, including from List and the keyboard, resets the
  ⇧-click range anchor.
- Saves write the file atomically to the chosen URL. Overwriting through
  `replaceItemAt` with a temp copy failed across volumes and left temp folders
  behind.
- Save Poster rejects HTTP error responses and removes its download once the
  panel closes.

## Validation

- `make build` and `make build-mac` pass.
- `make test-sim` (all app tests and DataProvider tests) passed on the booted
  iPhone 18 Pro simulator. `make test-app-mac` passed natively.
- `s4a`: grid arrows, row moves and scrolling, the ⇧-click range from the
  keyboard anchor, Escape, and the last-card boundaries. Window tabs share the
  sidebar scope. Inspector at the minimum width and with the sidebar collapsed.
- `s4b`: the scope change closes the inspector; a status edit keeps it open.
  Light appearance (forced per app with `-NSRequiresAquaSystemAppearance YES`,
  because System Settings could not be captured) for the grid, the list, and
  Settings. Japanese and Simplified Chinese launches: the main window,
  toolbar menu, context menu, Settings, and the Anime and File menus (read
  through accessibility) were translated, with nothing clipped.
- `s4c`: the glyph-only toolbar menu keeps its size; "2 Filters" title; Dock
  and Get Info icon; ⌘W keeps the app running, and a reopen event (`open` on the
  running app, as a Dock click sends) brings a library window back; ⌘Q quits in
  about 0.25 s with sync off.
- `s4d`, after the review fixes: commands are disabled after a scope change and
  after Escape; ⌥⌘I opens an entry in the current scope; a List selection
  anchors the next grid range. Poster and card saves, including Replace, gave
  valid JPEG and PNG files and left no temp files. A cross-volume overwrite, an
  HTTP error response, and a reminder click were not exercised.

## Open issues

These are shared with iOS. They were left unchanged because this branch keeps
iOS behavior as it is:

- In Light appearance, the white date, status and genre lines in the entry
  detail header sit on its fade into the page background and are hard to read.
- In Light appearance, the list rows' yellow score and cyan episode badges have
  weak contrast.
- Runtime totals such as "797h 14m" use the same unit letters in every
  language.

## Refs

- `MyAnimeList/Sources/Views/Library/LibraryGridView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView+Desktop.swift`
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryNavigationTitleCapsule.swift`
- `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`
- `MyAnimeList/Sources/Views/Sharing/AnimeSharingControlsSection.swift`
- `MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift`, `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift` (review fixes)
- `MyAnimeList/Resources/Assets.xcassets/AppIcon.appiconset/`
