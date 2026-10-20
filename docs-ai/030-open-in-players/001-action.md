# 030 — Open In Infuse and Kazumi: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-20 | Replaced the detail Safari button with an Open In menu that hid uninstalled apps. | — |
| 2026-10-20 | Maintainer asked for a list "quick action". It was first added to the shared context menu, then moved to a list swipe action after the maintainer clarified, then restored to the context menu as well at the maintainer's request. | — |
| 2026-10-20 | The swipe action was initially iOS-only on the mistaken belief that the Mac list had no swipe actions; added to `MacLibraryList` after the maintainer pointed this out. | — |
| 2026-10-20 | Uninstalled apps changed from hidden to disabled with a "Not Installed" subtitle, at the maintainer's request. | — |
| 2026-10-20 | Bangumi ID mapping deferred by the maintainer; this record written. | — |
| 2026-10-20 | Review fix: Kazumi queries now encode `+` as `%2B`; `URLComponents` leaves it literal, and Kazumi's Dart parser would decode it as a space (`BLOOD+` → `BLOOD`). Added a punctuation regression test. | — |
| 2026-10-20 | Moved the iOS Open In swipe action to the trailing edge beside Delete, with full swipe disabled. | — |
| 2026-10-20 | Maintainer screenshots showed the embedded iOS swipe Menu stretched the actions and left a gap on iPad. Replaced it with a plain button and a request identifying the originating row. | — |
| 2026-10-20 | Shortened the iOS swipe label to Open (開く / 打开), keeping Open In… for menus and the alert title. | — |
| 2026-10-20 | The iOS confirmation dialog omitted disabled apps. Switched to a native alert with disabled app buttons, the entry title, and Cancel; removed the installation-status message at the maintainer's request. | — |
| 2026-10-20 | Maintainer confirmed the resulting iPhone/iPad behavior and approved retaining these iOS changes. | — |
| 2026-10-20 | Maintainer reported that the Mac swipe menu does nothing and confirmed Delete also resets without a slide-back animation. Replaced that menu with a plain button and the existing SwiftUI alert, then moved Open to the trailing edge beside Delete at the maintainer's request. Animation changes are out of scope. | — |
| 2026-10-21 | Swapped Open and Delete so Open is the outermost, full-swipe trailing action on iOS and Mac, and added a device-local default swipe destination; see [002](002-swipe-default-destination.md). | — |
| 2026-10-21 | Maintainer found the settings `Picker` ignored `.disabled` on uninstalled apps on iOS. Replaced it with a menu of `Toggle`s on iOS and Mac. | — |

## Outcome and current state (as of 2026-10-21)

- The detail quick actions row, the library context menu (iOS and Mac), and the iOS
  and Mac list swipe actions all offer Open In… → Infuse, Kazumi, Homepage.
- On iOS the short Open button sits on the trailing edge beside Delete and opens a
  native alert with the entry title and Cancel. Unavailable apps stay visible as
  disabled choices. The Mac list uses the same plain button and native alert
  on the trailing edge beside Delete, matching iOS.
- Infuse links target the exact movie, series, or season by TMDb ID. Kazumi opens
  a title search (Chinese, then Japanese, then display title).
- Uninstalled apps are listed and disabled. Menus retain the "Not Installed"
  subtitle; the swipe alerts use disabled buttons without that message.
- Open is the outermost trailing swipe action and runs on full swipe. Settings →
  Interface → Open In → "Swipe Action Opens" (Ask Every Time, Infuse, Kazumi) makes
  the swipe open the chosen app directly; uninstalled apps are disabled there, and
  the swipe falls back to the alert when the chosen app can't open the entry. The
  preference is device-local (not synced, not backed up).

Key files:

- `MyAnimeList/Sources/Views/Library/EntryOpenInMenu.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryActionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryListView.swift`
- `MyAnimeList/Sources/Mac/MacLibraryList.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileInterfaceSections.swift`
- `MyAnimeList/Sources/Extensions/String+Extensions.swift` (`libraryOpenInSwipeDestination`)
- `MyAnimeList/Resources/Info.plist` (`LSApplicationQueriesSchemes`)
- `MyAnimeList/Resources/Localizable.xcstrings` ("Open In…", "Homepage", "Not Installed", "Open", "Open In", "Swipe Action Opens", "Ask Every Time")
- `MyAnimeList/Tests/MyAnimeListTests/EntryOpenInLinksTests.swift`

## Deviations from plan

The plan was written after the implementation, so it describes the final design. The
intermediate designs (hidden uninstalled apps, context menu only, swipe action only)
are recorded in the timeline.

## Validation

- Prior implementation record: the three `EntryOpenInLinksTests` passed on the
  booted iPhone 18 Pro simulator, and the native Mac build passed. These are
  earlier recorded results, not fresh validation for this commit.
- The original test file initially compiled into the app target. Its membership
  was corrected in both exception lists in `MyAnimeList.xcodeproj/project.pbxproj`.
- Maintainer runtime checks: the embedded iOS swipe Menu stretched the action
  group and left a gap on iPad; the confirmation dialog omitted disabled choices.
  The maintainer confirmed the final native alert looks good on iPhone and iPad.
- Focused iOS validation:
  `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/EntryOpenInLinksTests'`
  passed all three tests on the already-booted iPhone 18 Pro simulator.
- `make build-mac` passed with the request, alert, and swipe-button types shared
  across iOS and macOS.
- `git diff --check` passed. No additional agent visual checks were performed.
- The minimal Mac fix adds only presentation wiring and reuses existing actions;
  no new tests or repeat URL-test run were needed. Its visible behavior remains
  for maintainer acceptance. `make run-mac` launched successfully with the
  default 800-entry fixture, confirmed from the running process arguments.

- Amendment 002 (2026-10-21): `make test-app-sim
  APP_TEST_ONLY='MyAnimeListTests/EntryOpenInLinksTests'` passed all four tests on
  the already-booted iPhone 18 Pro simulator, and `make build-mac` passed. No
  runtime or visual check of the swipe order, full swipe, or settings picker was
  performed by the agent.

## Open questions

- Whether the settings menu's disabled `Toggle`s and "Not Installed" subtitles
  render as intended on iOS and Mac. Not yet checked at runtime; `make build` and
  `make build-mac` passed after the change.

- Whether the "Not Installed" subtitle (a second `Text` in the item's `Label`)
  renders as a subtitle in macOS menus. Unverified.
- Whether the Chinese-first Kazumi query actually finds titles better than the
  Japanese title. Unmeasured.
