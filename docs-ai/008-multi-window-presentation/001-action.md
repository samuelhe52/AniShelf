# 008 — Multi-window presentation: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-27 | Serialize duplicate repair and keep search per-window | `84a565e`, `eb83ce1` |
| 2026-09-27 | Scope reminder and share presentation to the invoking window | `956f2ec`, `5e96a46` |
| 2026-09-27 | Enable multiple windows and scope purchase confirmation | `801b1ed`, `e7dc6ab` |
| 2026-09-27 | Coordinate prompts/lifecycle and disconnected routes | `f114e82`, `f338086`, `a021aae`, `ac8f824` |

## Outcome and current state (as of 2026-10-07)

The checkout has a scene identifier reader, scene-aware share presentation,
window-local search, and app-wide lifecycle coordination. The commit series
records multi-window adoption and follow-up hardening, rather than only a manifest flag.

Key source files:

- `MyAnimeList/Sources/Views/Gadgets/WindowSceneIdentifierReader.swift`
- `MyAnimeList/Sources/Utils/ShareSheetPresenter.swift`
- `MyAnimeList/Sources/Views/SearchPage/SearchPage.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`

## Deviations from plan

Enabling multiple scenes was followed by explicit hardening of shared services
and routing. It was not sufficient by itself to establish scene correctness.

## Open questions

Prior memory explicitly says the early audit lacked a two-window runtime test.
Whether the Mac search crash is fixed on affected OS versions is unverified.
