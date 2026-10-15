# 020 — Native macOS feasibility and migration options: Plan

| Field | Value |
| --- | --- |
| Status | In progress |
| Anchor date | 2026-10-15 |
| Origin | Maintainer requested a whole-app native macOS feasibility assessment, then asked to preserve it on the existing Mac branch |
| Related | [Adaptive library](../005-adaptive-library/000-plan.md), [Background sync safety](../007-background-sync-safety/000-plan.md), [Multi-window presentation](../008-multi-window-presentation/000-plan.md), [Multi-selection invariants](../014-multiselect-invariants/000-plan.md) |

## Background

The question is whether AniShelf can gain a native SwiftUI macOS target with
AppKit integration while retaining iPhone and iPad support. This differs from
Mac Catalyst, which runs the UIKit-based application on macOS.

The existing Mac branch already contains Catalyst configuration (`7f72f3f`) and
Makefile targets (`8fffcfb`). It was renamed from `feature/mac-catalyst` to
`feature/native-macos` when this assessment was saved. The branch name expresses
the proposed direction; the application remains configured for Catalyst.
At this assessment's snapshot, `main` still uses Designed for iPhone/iPad on Mac.

The assessment is **medium-to-high complexity for a polished native macOS
version**. Direct UIKit usage is contained. The broader task is adapting
iOS-specific SwiftUI presentation, desktop interaction, window ownership, and
application lifecycle behavior. Much of the data and business logic is reusable.

This is a saved feasibility assessment and proposed approach. Authorizing this
record does not approve implementation. No native-target build or runtime
validation was performed, and no migration is claimed complete.

## Goals

- Preserve the reusable core and identify the platform boundaries before coding.
- Estimate the work required for feature parity and a polished desktop experience.
- Preserve local data, preferences, credentials, CloudKit state, and offline edits
  across any eventual transition from the existing Mac distribution.
- Keep iOS and macOS behavior understandable without duplicating the whole app.

## Evidence and assessment basis

Source inspection on 2026-10-15 found:

- `DataProvider/Package.swift` explicitly supports macOS 15 and iOS 18.
  Its 170 Swift source files have no direct UIKit markers in the source scan.
  Persistence and the `LibrarySync` CloudKit implementation already live there.
- Of 184 Swift files under `MyAnimeList/Sources/`, approximately 22 contain direct
  UIKit imports or UIKit-specific type references. This is an inventory heuristic,
  not a count of every file requiring migration: inferred UIKit colors and
  iOS-specific SwiftUI APIs extend the affected surface.
- The checked-out manifests for TMDb, Kingfisher, SwiftDraw, ZIPFoundation,
  AlertToast, and SHContainers declare macOS support. The resolved dependencies
  are listed in
  `MyAnimeList.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
  Manifest support is not proof that all app usage compiles on macOS.
- `MyAnimeList.xcodeproj/project.pbxproj` enables Catalyst on this branch, and
  `Makefile` uses `platform=macOS,variant=Mac Catalyst`. Neither establishes a
  native SwiftUI macOS target.
- The installed macOS 27 SDK headers mark `BGTaskScheduler` and
  `BGAppRefreshTaskRequest` unavailable on macOS. The existing reminder-refresh
  and background-execution design therefore needs a macOS-specific approach.

The reuse and complexity judgments below are inferences from these source
boundaries. The effort estimates are planning judgments, not measured delivery
times. Earlier Catalyst feasibility notes helped identify continuity and
lifecycle risks; current source and local SDK inspection corroborated those
risks rather than treating older platform settings as current.

## Design / approach

Keep a shared core and introduce platform-specific app, navigation, and
integration layers. Reuse SwiftUI detail content where its semantics fit both
platforms. Give the Mac library toolbar, selection behavior, settings
presentation, and window coordination deliberate desktop implementations.
Concrete new target and file names remain undecided.

| Area | Existing source anchors | Proposed work | Difficulty |
| --- | --- | --- | --- |
| Shared core | `DataProvider/Package.swift`, `DataProvider/Sources/LibrarySync/`, `MyAnimeList/Sources/Network/` | Retain persistence, sync transport, metadata fetching, and portable business logic; validate actual macOS compilation | Low–medium |
| SwiftUI compatibility | `MyAnimeList/Sources/Views/Library/LibraryToolbar.swift`, `MyAnimeList/Sources/Views/SearchPage/SearchPage.swift`, `MyAnimeList/Sources/Views/Library/LibraryEntryInteractionState.swift` | Adapt navigation-bar modifiers, bottom toolbars, search placement, UIKit colors, size-class policy, and edit mode | Medium; distributed across views |
| Desktop interaction | `MyAnimeList/Sources/Views/Library/LibraryListView.swift`, `MyAnimeList/Sources/Views/Library/Categories/LibraryCategoryStrip.swift`, `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsView.swift` | Design keyboard focus, shortcuts, Shift/Command selection, pointer dragging, menus, and settings presentation | High for polish |
| Window ownership | `MyAnimeList/Sources/Views/Gadgets/WindowSceneIdentifierReader.swift`, `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift`, `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileCloudSyncController.swift` | Replace UIKit scene identifiers and controller traversal with macOS window and presentation ownership | Medium–high |
| Sync and notifications | `MyAnimeList/Sources/App/MyAnimeListApp.swift`, `MyAnimeList/Sources/App/LibrarySyncNotificationBridge.swift`, `MyAnimeList/Sources/App/LibrarySyncBackgroundExecutionController.swift` | Adapt delegate callbacks, APNs routing, termination/sleep behavior, pending sync, and reminder refresh | Medium–high |
| Images and sharing | `MyAnimeList/Sources/ViewModels/Sharing/SharingCardExportPipeline.swift`, `MyAnimeList/Sources/ViewModels/Sharing/SharingCardRenderer.swift`, `MyAnimeList/Sources/Extensions/UserEntryInfo+Pasteboard.swift` | Adapt image representation, pixel-scale handling, rendering/encoding, pasteboard, and share presentation | Medium |
| Existing-user continuity | `DataProvider/Sources/DataProvider/DataProvider.swift`, `MyAnimeList/Sources/Utils/TMDbAPIKeyStorage.swift`, `MyAnimeList/MyAnimeList-macCatalyst.entitlements` | Verify store location, sandbox access, preferences, Keychain, CloudKit metadata, and offline changes under the intended app identity | High validation importance |

Two examples explain why this exceeds mechanical API substitution:

- `LibraryListView` gates list selection behind explicit multi-selection mode.
  Desktop selection must reconcile ordinary browsing, keyboard navigation,
  batch operations, and inspector focus.
- `SharingCardExportPipeline` uses `UIImage`, image-scale assumptions, and
  `ImageRenderer.uiImage`. A native export path must preserve output pixel sizes,
  color space, transparency, and supported codecs.

### Provisional effort

For one experienced developer, retaining current features and iOS support:

| Milestone | Estimated cumulative effort | Expected evidence |
| --- | --- | --- |
| Feasibility spike | 2–5 developer-days | Native target and actual compiler/dependency blocker inventory |
| Usable main workflows | 2–4 developer-weeks | Library browsing, search/add, detail/edit, and core integrations exercised on macOS |
| Polished feature parity and release validation | 6–10 developer-weeks | Desktop interactions, continuity, lifecycle, sandbox, signing, and regression acceptance |

These are cumulative ranges, not additive stages or commitments. A native-target
spike should revise them. Minimum macOS version, UI redesign scope, and
distribution/upgrade continuity can materially change the estimate.

## Alternatives & decisions

| Option | Assessment and current disposition |
| --- | --- |
| Shared core with platform-specific app and integration layers | Recommended starting architecture; preserves reusable code while making behavioral differences explicit. This remains a proposal. |
| Continue with Catalyst | Existing branch baseline and a lower-scope route for retaining UIKit behavior. It does not establish feasibility of the native SwiftUI/AppKit target being evaluated. No decision to discard this work has been made. |
| Separate full Mac rewrite | Would duplicate data and business logic despite existing portable modules. The source assessment does not justify that cost. |
| Conditionalize all existing views in place | Appropriate for small API substitutions, but pervasive conditionals would make navigation, selection, and window ownership harder to reason about. Prefer explicit platform layers for those behaviors. |

## Validation and acceptance criteria

Before treating a native implementation as feasible or complete:

1. Build a native macOS target against the resolved dependencies and record the
   actual compiler blockers. Current `make build-mac` targets Catalyst; native
   Makefile support would be part of the proposed implementation.
2. Exercise library list/grid browsing, categories/reordering, search and add,
   detail/edit, batch actions, poster selection, sharing, backup/restore,
   reminders, settings, purchases, and recovery screens on macOS.
3. Manually validate keyboard focus, menu commands, Shift/Command selection,
   pointer interactions, resizing, sheets/popovers, multiple independent
   windows, last-window close, termination, and sleep/resume. Passing a build
   cannot establish visual or runtime behavior.
4. Use fakes/local tests for sync while adapting lifecycle hooks. Live CloudKit
   writes require the maintainer's explicit permission. Test notifications,
   offline changes, pending-sync completion, and reminder behavior under an
   agreed runtime validation plan.
5. Validate migration using copies of representative existing stores and an
   agreed distribution identity. Check preferences, Keychain access, sandbox
   permissions, local data, sync metadata, and upgrade behavior separately;
   matching bundle identifiers alone does not prove continuity.
6. Run focused tests for distinct changed behavior and appropriate iOS regression
   checks through the Makefile. Use an already booted simulator; do not boot one
   without explicit permission.

Only source, project configuration, dependency manifests, and SDK availability
were inspected for this assessment. No build, tests, launch, signing check,
upgrade migration, visual acceptance, or live CloudKit write was performed.
No action record is warranted until implementation proceeds.

## Open questions

- Which minimum macOS version should the native app support?
- Should the first version preserve the current library structure, or redesign
  navigation around desktop sidebars, toolbars, and settings windows?
- How should ordinary selection, inspector focus, and batch selection interact?
- Are native window tabs required, and which browsing state belongs to each window?
- What reminder-refresh behavior is required while the app is closed?
- What app identity, distribution route, and upgrade path should be supported?
- Which dependencies or APIs fail in an actual native-target build?

## Platform references

- [Apple: Mac Catalyst](https://developer.apple.com/documentation/uikit/mac-catalyst)
- [Apple: AppKit](https://developer.apple.com/documentation/appkit)
- [Apple: NSApplicationDelegate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate)

## Amendments

- Updated 2026-10-15: Implementation approved; open questions resolved and slices planned — see [002-implementation-decisions.md](002-implementation-decisions.md)
- Updated 2026-10-15: Slice 1 — native build and launch — see [003-slice-1-native-build.md](003-slice-1-native-build.md)
- Updated 2026-10-16: Slice 2 — Mac shell (sidebar split view, desktop selection, inspector layout, commands, Settings window) — see [004-slice-2-mac-shell.md](004-slice-2-mac-shell.md)
