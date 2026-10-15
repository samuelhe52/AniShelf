# 020.003 — Slice 1: native build and launch

## Context

First slice of [002-implementation-decisions.md](002-implementation-decisions.md):
make the existing app target build and run natively on macOS without
redesigning any UI. Implemented by Codex (GPT-6 Astra) on 2026-10-15 and
reviewed by Claude Code.

## Change

- The `MyAnimeList` target now lists `macosx` in `SUPPORTED_PLATFORMS`, with
  `MACOSX_DEPLOYMENT_TARGET = 26.0` and `SUPPORTS_MACCATALYST = NO`. The
  Catalyst entitlements file became `MyAnimeList/MyAnimeList-macOS.entitlements`
  (sandbox, network client, user-selected files, CloudKit, KVS, and
  `com.apple.developer.aps-environment`). Test targets remain iOS-only for now.
- The Mac Makefile targets use `platform=macOS` and pass
  `-allowProvisioningUpdates`. The first Mac build failed because no Mac App
  Development profile existed; automatic provisioning created one.
- Removed the `SHContainers` package. Nothing imported it, and it does not
  compile for macOS (UIKit-only system colors). Patching an unused dependency
  was rejected.
- Compile blockers were resolved with small shims rather than redesign:
  `MyAnimeList/Sources/Utils/PlatformImage.swift` (NSImage/UIImage alias plus
  pixel-size helpers used by the sharing export pipeline),
  `MyAnimeList/Sources/Utils/PlatformViewModifiers.swift` (semantic colors,
  toolbar placements, iOS-only modifiers as Mac no-ops, a Mac size class that is
  always regular), and `#if os(macOS)` branches for pasteboard, window identity
  (an `NSWindow` object-identity string in place of the UIScene persistent
  identifier; corrected 2026-10-16 from `windowNumber`, see
  [004](004-slice-2-mac-shell.md)), share
  presentation (`NSSharingServicePicker`), text editing, page dots, and
  category-strip gestures. Every iOS branch keeps its previous code.
- `MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift` provides the Mac
  `LibrarySyncNotificationBridge` (an `NSApplicationDelegate` that registers for
  remote notifications and forwards pushes to the sync handler) and a minimal
  `LibrarySyncBackgroundExecutionController`.

### Deferred to slice 3

Periodic reminder refresh (no-op on Mac), sleep/termination protection for an
in-flight sync, local-notification presentation and tap routing, and native app
tests.

## Validation

Run by Codex on 2026-10-15; reports and logs are in the untracked
`.build/mac-review/s1/` directory.

- `make build-mac` and `make build` both passed.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/AnimeSharingTests MyAnimeListTests/TMDbImageAndTranslationTests MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests'`:
  42 tests passed on the already booted iPhone 18 Pro (iOS 27) simulator.
- Continuity: the native build opened
  `~/Library/Containers/8F8741C4-…/Data/Library/Application Support/DataProvider/mal.store`,
  the same UUID container whose metadata names `com.samuelhe.MyAnimeList` and
  that the iPad-on-Mac and sandboxed Catalyst builds used. It showed all 137
  displayed entries (143 rows). The TMDb key loaded without a Keychain prompt.
  The store was backed up with hashes before the first launch. CloudKit sync was
  not exercised.
- A computer-use walkthrough confirmed the app runs as an iPad-style layout in a
  Mac window. The issues it found are inputs to slice 2: the category manager
  sheet collapses, gallery sizing is poor, settings is an overlay, sheets have
  inconsistent dismissal, and toolbar items overflow at narrow widths.

## Refs

- Files: `MyAnimeList.xcodeproj/project.pbxproj`, `Makefile`,
  `MyAnimeList/MyAnimeList-macOS.entitlements`,
  `MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift`,
  `MyAnimeList/Sources/Utils/PlatformImage.swift`,
  `MyAnimeList/Sources/Utils/PlatformViewModifiers.swift`.
