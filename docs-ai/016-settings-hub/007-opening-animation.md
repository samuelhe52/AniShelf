# 016.007 — Settings opening animation

## Context

Commit `0239bdd4` replaced the original profile settings transition with a zoom from the library toolbar button. After a few days of use, the maintainer found the original animation more fitting.

## Change

Restore the original overlay and its profile settings transition, rather than the toolbar zoom and full-screen cover. This restores the prior opening and closing behavior on iOS; the native Mac settings scene is unchanged.

## Refs

- `a18388b6` reverts the behavior introduced by `0239bdd4`.
- `MyAnimeList/Sources/Views/Library/LibraryView.swift`
- `MyAnimeList/Sources/Views/Library/LibraryViewTransitions.swift`
