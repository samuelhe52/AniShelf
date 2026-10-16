# 024 — Mac inspector entry switch without a flash: Plan

| Field | Value |
| --- | --- |
| Status | Implemented on `feat/native-macos` (`c4cab57`) |
| Anchor date | 2026-10-17 |
| Origin | Maintainer report with a screen recording: switching the selected entry on the Mac flashes the inspector. Written after step 1 below was coded and before steps 2–4. |
| Related | [021-mac-selection-model](../021-mac-selection-model/000-plan.md), [022-mac-library-root-split](../022-mac-library-root-split/000-plan.md) |

## Background

On the native Mac build, selecting a different entry made the inspector go dark
for about a quarter second. Frame analysis of the recording (inspector-region mean
brightness per frame) showed the drop on the first frame of the switch while the
old title was still fully visible, a ramp while the old and new text cross-faded,
and a snap back exactly when the fade ended.

Root cause, from source plus the frame timing:

- `EntryDetailView` gives its scroll content `.id(session.instanceID)`,
  `.transition(.opacity)`, and `.animation(entryReplacementAnimation, value:
  session.instanceID)` (0.18 s). `4a42031` added this in July so the iPad
  inspector cross-fades when the shown entry changes.
- `MacLibraryInspector` keeps one `EntryDetailView` and hands it a new session per
  selection, so every Mac selection change runs that cross-fade.
- During an opacity transition the subtree is drawn as flattened layers, and the
  inspector's material cards (`.thinMaterial` and the inspector backdrop) render
  flat dark until the transition ends. This mechanism is inferred from the timing;
  it was not instrumented.

Removing the fade alone would expose a second problem the fade was hiding: a new
`EntryDetailSession` started with an empty `EntryDetailViewModel` (blank title, no
stat cards). The view's `.task` filled it from the stored `entry.detail` a pass
later, and a cached detail without a logo always triggered a TMDb refetch that
applied a third time. Content filled in and shifted after the switch.

## Goals

- A Mac selection change shows the new entry complete in the same frame, with no
  dark flash: the Mail and Finder convention for inspector and preview panes.
- Content that only the network can supply fills in place with a short fade
  instead of popping.
- Keep the iPad inspector's entry cross-fade.

### Non-goals

- Animating the single-to-batch inspector change and the grid selection ring are
  separate follow-ups.
- The one-pass window in which `MacLibraryInspector` has no session for a new
  selection (`session(for:)` returns nil until `onChange` runs) was not visible in
  the recording and stays as is.

## Design / approach

1. **Fill from storage synchronously.** `EntryDetailViewModel.prepare(for:language:)`
   resets the fields and applies the stored detail. `EntryDetailSession.init` calls it
   with `Language.resolvedAnimeInfoLanguage()`. `load(for:language:)` calls `prepare`
   (a no-op for the prepared request) and then only fetches.
2. **No switch fade on the Mac.** `entryReplacementAnimation` becomes `nil` on macOS.
   The `.id(session.instanceID)` stays so per-entry scroll and view state reset.
3. **No logo-only refetch on the Mac.** The Mac header never shows the title logo,
   so on macOS a stored same-language detail counts as current even without a logo.
4. **Fade only network refreshes.** The view model bumps a revision when a fetched
   detail is applied. `EntryDetailView` animates on that revision, not on the
   session, so a refresh after a switch cross-fades changed text and inserts new
   sections smoothly.

Files: `MyAnimeList/Sources/ViewModels/Library/EntryDetailViewModels.swift`,
`MyAnimeList/Sources/Models/Library/EntryDetailSession.swift`,
`MyAnimeList/Sources/Views/Library/EntryDetail/EntryDetailView.swift`.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Instant swap on the Mac | Mail, Finder, Notes, and Xcode swap their inspector or preview content instantly. People arrow through lists quickly; a fade adds latency and smears consecutive presses. Any opacity transition over the material cards also brings back the dark flash. |
| Skip the fade with `#if os(macOS)` | `detailHost == .inspector` would also disable the iPad inspector fade the animation was added for. |
| `nil` animation over removing the modifier | `.animation(nil, value:)` also strips an animation inherited from an outer transaction, so the swap stays instant whatever triggered it. |
| Prepare in the session initializer | Doing it in the view (`onAppear` or `.task`) runs after the first frame, which is the bug. The session is created where the selection is synchronized, before the detail renders. |
| Keep logo-based refetch on iOS | The iOS hero shows the logo, and the refetch backfills it for details cached before logos were stored. The Mac has no logo UI. |
| Revision-keyed refresh animation | Keying on the session would animate switches again. Keying on individual fields would miss inserted sections. |

## Validation and acceptance criteria

- Extend `EntryDetailSessionTests` / `EntryDetailViewModelTests`: a new session shows
  the stored title before loading; on macOS a logo-less cached detail does not fetch.
- `make test-mac` and `make test-app-sim` with those suites.
- `make run-mac`: switching entries shows no dark flash and no late reflow for stored
  entries; the maintainer does the visual pass.

## Amendments

None yet.
