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

## Outcome and current state (as of 2026-10-20)

- The detail quick actions row, the library context menu (iOS and Mac), and the iOS
  and Mac list leading swipe actions all offer Open In… → Infuse, Kazumi, Homepage.
- Infuse links target the exact movie, series, or season by TMDb ID. Kazumi opens
  a title search (Chinese, then Japanese, then display title).
- Uninstalled apps are listed, disabled, and labelled "Not Installed".

Key files:

- `MyAnimeList/Sources/Views/Library/EntryOpenInMenu.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryEntryActionState.swift`
- `MyAnimeList/Sources/Views/Library/LibraryListView.swift`
- `MyAnimeList/Sources/Mac/MacLibraryList.swift`
- `MyAnimeList/Resources/Info.plist` (`LSApplicationQueriesSchemes`)
- `MyAnimeList/Resources/Localizable.xcstrings` ("Open In…", "Homepage", "Not Installed")
- `MyAnimeList/Tests/MyAnimeListTests/EntryOpenInLinksTests.swift`

## Deviations from plan

The plan was written after the implementation, so it describes the final design. The
intermediate designs (hidden uninstalled apps, context menu only, swipe action only)
are recorded in the timeline.

## Validation

- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/EntryOpenInLinksTests'` on the
  booted iPhone 18 Pro simulator: 3 tests passed, after the final change.
- `make build-mac`: build completed, after the final change.
- The first test run failed to compile because the new test file was compiled into
  the app target. Fixed by adding it to both membership exception lists in
  `MyAnimeList.xcodeproj/project.pbxproj`.
- No runtime UI check was run.

## Open questions

- Whether a `Menu` inside `.swipeActions` presents its items when tapped on every
  supported iOS version. Unverified.
- Whether the "Not Installed" subtitle (a second `Text` in the item's `Label`)
  renders as a subtitle in macOS menus. Unverified.
- Whether the Chinese-first Kazumi query actually finds titles better than the
  Japanese title. Unmeasured.
