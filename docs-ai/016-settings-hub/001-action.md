# 016 — Settings hub: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-13 | Read the approved HTML plan and wrote 000-plan.md before code. | `3b3d07b` |
| 2026-10-13 | Implemented flat navigation, focused settings sections, live hub status, and stable presentation ownership. | `3b3d07b` |
| 2026-10-13 | Added translations and focused tests; updated app tutorials and three website guide locales. | `3b3d07b`, `03397d1`; site `2a37952` |
| 2026-10-13 | Samuel withdrew further visual checks and will perform them himself. | User instruction |

## Outcome and current state (as of 2026-10-13)

The profile retains its LibraryView overlay and close callback. The hero, 2×2
statistics, and Library Details precede six hub destinations. One root-owned path
and navigationDestination serve all sizes; only the hub's column count adapts.
(Corrected 2026-10-13: the first delivery linked the hero to a Library Overview
page holding Library Details; [002](002-visual-review.md) reverted that.) TMDb and iCloud are inline sections.

Existing storage keys/defaults, toggle side effects, destructive confirmations,
scene-aware What's New/export routing, and sheet sizing are retained. Cloud action
and alert state now live at the root. Pending conflicts wait for active operations,
root presentation flags, and the scene's actual modal hierarchy; the short polling
task only runs while a conflict is pending and cancels with root lifetime/status.
This also covers UIKit share sheets without changing sharing APIs. Reminder reload
runs at the root on appearance/foreground, with an initial loading indicator.

Shared sync issue derivation feeds both the hub and sync detail section. Restoration
failures are counted separately without counting the pending-reconstruction list
again. Successful sync does not hide outstanding issues. Source inspection, rather
than end-to-end cloud testing, establishes preservation of the operation wiring.

### Files added

- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileCloudSyncController.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsHub.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsPages.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryProfileSettingsStateTests.swift`
- `docs-ai/016-settings-hub/000-plan.md`
- `docs-ai/016-settings-hub/001-action.md`

### Files changed

- `MyAnimeList.xcodeproj/project.pbxproj`
- `MyAnimeList/Resources/Localizable.xcstrings`
- `MyAnimeList/Sources/Models/Library/LibraryProfileSettingsModels.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsComponents.swift` (added by 002)
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileAiringReminderSettingsSection.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileDataManagementSections.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileInterfaceSections.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfilePreferenceSections.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsDisplaySupport.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsView.swift`
- `MyAnimeList/Tests/MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests.swift`
- `docs-ai/README.md`
- `docs/anishelf_overview.en.md`
- `docs/anishelf_overview.md`

The sibling website's existing `src/content/docs/en/guide.md`,
`src/content/docs/zh/guide.md`, and `src/content/docs/ja/guide.md` were updated
under `../anishelf-site/` to use the new settings destinations.

### File deleted

- Former `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsCard.swift`:
  its expanded layout was replaced; operation state/actions were moved to the root.

## Deviations from plan

- Overview reused the existing details card inside the shared destination wrapper
  instead of a proposed LibraryProfileOverviewPage.swift. The page was later
  removed (002).
- Added matching tutorial/website guide changes because AGENTS.md requires the
  website to follow changed user-facing feature names and navigation.
- Repository-wide make format also reformatted six unrelated files. Those exact
  formatting-only hunks were reverted to keep this change scoped; existing lint
  warnings in those and other untouched files remain.
- Further visual verification was stopped at Samuel's request. No other simulator
  was booted. No staging, commits, pushes, or publication were performed.

## Validation

- `make build`: passed, including the final operation-guard revision.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests MyAnimeListTests/LibraryProfileSettingsStateTests'`:
  initial run passed all 5 Swift Testing tests (the XCTest shim reports 0 separately).
  Final rerun also passed all 5 tests, including deferral while a sync action is still in flight.
- `make run-sim`: passed build/install/launch on the existing iPhone 18 Pro, iOS 27.
- `make format`: completed successfully. An introduced documentation-comment warning
  was corrected; unrelated formatter changes were removed as described above.
- `make lint`: exit 0, with 27 existing warnings in untouched files and no warnings
  in the changed settings source/tests.
- `git diff --check`: passed in both app and website checkouts.
- Website `npm run check`: 45 files, 0 errors, 0 warnings, 0 hints.
- Website `npm run build`: passed, 16 pages built. No deployment.
- Before the stop request, visually inspected the Japanese iPhone hub and
  Library & Tracking page, and confirmed Back returns to the hub. Navigation/reveal
  state is retained in source; the tool's delayed frames did not reliably establish
  animation timing. Overview (since removed) was not visually verified.

No build or test failures occurred. Device Hub automation errors during visual
checks were tooling failures, not app failures.

## Open questions / remaining manual verification

Samuel verified the remaining checks on 2026-10-13: all destinations, animation
timing on Back, iPad layout/resizing, Dynamic Type, dark mode, other locales,
the live-service flows (iCloud conflicts during a modal, import/restore/export,
notification permissions), and website light/dark and responsive layout. The
later amendments (003–005) were covered by the same review. The Chinese 你/您
mix ([002](002-visual-review.md)) was resolved to 你.
