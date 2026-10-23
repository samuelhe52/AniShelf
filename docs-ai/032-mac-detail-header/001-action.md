# 032 — Mac detail header modes: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-23 | Inspected current compact header and the earlier shared hero in `b080549^`; wrote the plan before implementation. | `000-plan.md` |
| 2026-10-23 | Added the local Compact/Cinematic setting, shared hero selection, translations, and website guide copy. | Working tree; no commit requested |
| 2026-10-23 | Fixture UI review reproduced portrait-fallback overflow and a misplaced bottom fade; constrained hero layers to the measured viewport. | `EntryDetailHeaderComponents.swift` |
| 2026-10-23 | Amendment 1: Mac hero fades by mask, uses a lighter top scrim, runs under the toolbar at 412 points with centered quick actions; fixture entries gain full details (`9271e87`); logo refetch uses only the per-call flag; trimmed overlapping tests. | `000-plan.md` amendment 1 |

## Outcome and current state (as of 2026-10-23)

Settings → Appearance & Interaction → Entry Details offers a Detail Header picker.
Compact remains the default. Cinematic uses the shared background artwork (412 points on the Mac, running under the toolbar and fading to transparent)
and logo/title header, with the native Mac quick actions below it. The lower Mac
tracking controls and grouped cards remain shared between modes. `@AppStorage`
updates the header live without replacing its session.

Opening Cinematic also requests a missing logo from older cached metadata. A
successful metadata request records that logos were checked, so toggling modes
does not repeatedly fetch titles for which the service has no logo. Compact
continues using its same-language cache without requiring a logo.

The preference is excluded from both backup and CloudKit allowlists. Cinematic
clears the compact poster's batch-flight source because no small poster is visible.
The shared hero's artwork, scrims, and text now stay within its measured width and
height, including when a portrait poster is the available artwork.

Key files:

- `MyAnimeList/Sources/Mac/MacEntryDetailHeader.swift`
- `MyAnimeList/Sources/Extensions/String+Extensions.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`
- `MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailHeaderComponents.swift`
- `MyAnimeList/Sources/ViewModels/Library/EntryDetailViewModels.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileInterfaceSections.swift`
- `MyAnimeList/Resources/Localizable.xcstrings`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryPreferenceDefaultsTests.swift`
- `MyAnimeList/Tests/MyAnimeListTests/EntryDetailViewModelTests+Loading.swift`

The sibling `anishelf-site` checkout's English, Chinese, and Japanese guides also
describe the setting, using the app's localized control names. Nothing was published.

## Deviations from plan

The shared hero needed a sizing fix revealed by actual Mac fixture review; simply
reusing it allowed a portrait fallback to draw past the declared height and put
the title over the controls below it. This fix also compiles for iOS, but mobile
runtime was not reviewed during this task.

## Validation

- `make build-mac`: passed.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/LibraryPreferenceDefaultsTests'`:
  all 13 tests passed, including exclusion of the new preference from backup/sync.
- After adding logo loading, `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/EntryDetailViewModelTests MyAnimeListTests/LibraryPreferenceDefaultsTests'`:
  47 tests passed, zero failures/skips, confirmed in the Xcode result summary.
  The new parameterized case covers both a returned logo and a successful response
  without one, including switching from cached Compact detail and repeated toggles.
- `make build`: passed again after the shared hero sizing and logo-loading changes.
- `make run-mac`: the first launch failed with RBS Code 5 / POSIX 163; signature
  verification passed and subsequent `make launch-mac` / `make run-mac` succeeded.
  No signing or project-configuration workaround was applied.
- Native computer-use screenshots: reviewed the Compact header, localized settings
  picker, live change to Cinematic, persistence across fixture relaunches, portrait
  fallback/title rendering, 340-point inspector wrapping, and switching to a batch
  selection. The corrected title and bottom fade stay above the action buttons.
  Screenshots were viewed locally and are not retained as repository evidence.
- A launch with `-AppleInterfaceStyle Dark` did not produce dark appearance; dark
  Mac visual verification remains open.
- Focused Swift formatting lint and `git diff --check`: passed after formatting.
- Website `npm run check` and `npm run build`: passed. Safari loaded a temporary
  page containing the three guides at desktop/390px widths and light/dark color
  schemes, but its screenshot surface returned a small distorted window thumbnail.
  This did not establish website visual acceptance; the temporary page was removed.

## Amendment 1 validation

- `make build-mac` and `make build`: passed. Focused `swift format` and `git diff --check`: clean.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/EntryDetailViewModelTests MyAnimeListTests/LibraryPreferenceDefaultsTests'`: passed.
  Removed the platform-branching logo test (covered by the parameterized title-logo test) and
  the key-absence preference test.
- Fixture screenshots via `screencapture -l`: Cinematic fades into the inspector material
  with no seam and keeps the score/status controls in view; text titles, generated logos,
  subtitle/metadata/genre lines overlap the fade as on iOS and stay legible; quick actions are centered; Compact
  unchanged. Real title logos remain unverified.
- Maintainer visual pass of the under-toolbar hero: cards under the toolbar, bright
  artwork, overscroll, live mode switching, inspector widths, and dark mode all checked out.
- Found, not fixed: the inspector's restored selection at launch starts two loads; the
  newer one is cancelled with its view and the older result is discarded as stale, so the
  restored entry shows only stored values until reselected. Predates this change.

## Open questions

- The fixture has generated posters, no real title logos, and a placeholder TMDb
  key. Real logo/metadata rendering and empty-artwork runtime fallback still need
  acceptance with real content. Their existing shared rendering paths were reused.
- Mobile runtime after the shared sizing correction were
  not visually verified. No simulator was booted.
- Website visual acceptance at all locale/theme/width combinations remains open
  because the available Safari screenshot surface was unusable for that check.
