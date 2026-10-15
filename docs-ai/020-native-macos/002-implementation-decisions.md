# 020.002 — Native macOS implementation decisions

## Context

On 2026-10-15 the maintainer approved implementing the native macOS app on
`feat/native-macos` and delegated product and design decisions to the
implementing agents (Claude Code as lead/reviewer, Codex as main implementer
with computer-use UI inspection). `main` must not change, and nothing is
pushed until the maintainer asks. The maintainer confirmed that the local
library and the CloudKit development environment used by Debug builds may be
read and written freely; production user data lives in the CloudKit production
environment. Purchases stay in StoreKit test/sandbox flows.

This amendment resolves the open questions in [000-plan.md](000-plan.md) and
sets the slice plan. Each slice records its outcome in a later amendment;
`001-action.md` is written when the last slice lands.

## Change

### Decisions

| Topic | Decision | Reason and rejected alternative |
| --- | --- | --- |
| Target shape | Convert the existing `MyAnimeList` app target into a multiplatform target (iOS + native macOS) and turn Catalyst off. | One target keeps one file membership list, one test host, and one bundle identity. A second macOS target would duplicate build settings and the synchronized-group membership exceptions that already trip new test files (see [008](../008-multi-window-presentation/000-plan.md) notes). Keeping Catalyst was rejected because it is not the native AppKit/SwiftUI app this work exists to build. |
| App identity | Keep `com.samuelhe.MyAnimeList`, the same iCloud container, and a sandboxed Mac build. | Same identity allows universal purchase and lets the sandboxed native build reuse the container that the iPad-on-Mac and sandboxed Catalyst builds already use (recovered: Catalyst reused it on 2026-10-15). Continuity must still be verified at runtime, per 000-plan criterion 5. |
| Minimum macOS | macOS 26.0. | Matches the iOS 26.0 app deployment target, so both platforms share the same SwiftUI and Liquid Glass API surface with few availability branches. Older macOS would add branches for little audience benefit. |
| Code organization | Small API differences use `#if os(macOS)` or small platform shims in the shared file. The Mac app shell (window scene, sidebar, toolbar, commands, Settings scene, AppKit bridges) lives in Mac-only files under the proposed `MyAnimeList/Sources/Mac/` folder. iOS behavior must stay unchanged. | Follows 000-plan's "explicit platform layers" recommendation. Navigation, selection, and window ownership differ enough that conditionalizing iOS views throughout would be harder to read. |
| Main window | `NavigationSplitView` with a sidebar (library scopes, see Sidebar below), the existing gallery/list as content, and entry detail in the trailing inspector. | Standard Mac library-app structure (Music, Photos, Finder). Reuses the iPad inspector detail path instead of pushing navigation. The iPhone-style category strip is replaced by the sidebar on Mac. |
| Selection | Native click / Cmd-click / Shift-click selection with keyboard navigation. One selected entry shows its detail in the inspector; several show a batch summary and batch actions. No explicit "Select" mode on Mac. | Desktop users expect selection without a mode switch. The multi-select snapshot invariants in [014](../014-multiselect-invariants/000-plan.md) must keep holding on iOS; the Mac path may use its own selection state. |
| Search and add | Toolbar search field filters the library (Cmd-F). Adding from TMDb is a dedicated "Add Anime…" command (Cmd-N) that presents the TMDb search in a sheet. | Separates "find in my library" from "add new" instead of mirroring the iOS mode switch inside one field. |
| Settings | Native `Settings` scene (Cmd-,) built from the existing settings sections, instead of the full-window overlay, laid out as a System Settings–style sidebar (Overview plus the six settings pages). | Mac convention; frees the main window from a modal overlay. Corrected 2026-10-16 from "tabbed" — see [004](004-slice-2-mac-shell.md). |
| Windows | `WindowGroup` with multiple windows and native tabs. Per window: selection, inspector, search text. Shared across windows: sidebar scope, filters, sort, grouping, view style (existing [008](../008-multi-window-presentation/000-plan.md) decision). Closing the last window leaves the app running. | Matches existing multi-window decisions and standard macOS app lifecycle; keeping the app alive lets sync and reminder refresh continue. Sidebar scope is shared because it maps onto `LibraryStore.filters` and `activeCategoryID`, which are store-level shared state; making it per window would mean splitting browse state out of `LibraryStore`, which was not judged worth it. |
| Sidebar | Smart lists (All, Watching, Plan to Watch, Watched, Dropped, Favorites) and a Categories section. Choosing a row sets one scope: a status row sets that single filter and clears the category; a category row sets the category and clears filters; All clears both. Combined filters remain available from the toolbar menu; the sidebar then shows no selection. | Gives categories and statuses a visible home on a wide screen. Two independent sidebar selections (status × category) were rejected as confusing. |
| Background work | `BGTaskScheduler` is unavailable on macOS. Refresh reminders and sync on launch, on activation, and periodically with `NSBackgroundActivityScheduler` while the app runs. Already scheduled local notifications fire while the app is closed. CloudKit pushes arrive through an `NSApplicationDelegate` adaptor. | Closest supported equivalent; no login item or helper process, which would add a second app identity. |
| Images, sharing, pasteboard | A small platform image shim; `ShareLink` or `NSSharingServicePicker` for share; `NSPasteboard` for copy; `ImageRenderer.nsImage`/`cgImage` for card export with the same pixel sizes as iOS. | Keeps one export pipeline with platform-specific edges, per 000-plan's image notes. |
| Menus and shortcuts | File (New Window, Add Anime…, Import/Export), View (Gallery/List, Show Sidebar, Show Inspector, sort/group), Entry actions in menus and context menus, standard Edit menu behavior. | Mac users expect commands to be reachable from the menu bar with shortcuts. |

### Slices

1. **Native build and launch.** Native macOS destination builds, the app
   launches against the existing container, compile blockers are resolved with
   the smallest shims, and every existing screen is screenshotted as a
   baseline. iOS build stays green.
2. **Mac shell.** Split view, sidebar, toolbar, inspector, desktop selection,
   menu commands, Settings scene.
3. **Feature parity.** Search/add, detail/edit, poster selection, sharing,
   backup/restore, reminders and notifications, purchases, startup recovery,
   sync lifecycle.
4. **Polish and validation.** Keyboard and focus, windows and tabs, resizing,
   light/dark, localization, focused tests, iOS regression, Makefile targets.

## Refs

- Branch `feat/native-macos`; baseline commit `7f26492`.
- [000-plan.md](000-plan.md) open questions resolved here.
