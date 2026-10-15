# 018.002 — Language gets its own settings page again

## Context

After reviewing the first build, the maintainer reported two problems on 2026-10-15.
First, the Japanese copy in the inline hub row was too long. "デフォルトの ポスター" wrapped
onto two lines, the fallback caption ran to three lines, and the menu capsule was truncated
to "アニメ情報…". Second, Language should have its own page again. In
[016.003](../016-settings-hub/003-inline-language.md) it was moved inline because it held a
single control. With Default Poster added, that reason no longer applies.

## Change

| Choice | Decision and alternative |
| --- | --- |
| Placement | `LibraryProfileSettingsDestination.language` ("Language") is restored as the first hub destination. Its hub row value shows the resolved language (`System (%@)` or the chosen language), like the pre-016.003 row. On iPad, the workspace shows it as the first titled group. Rejected: keeping the inline row and only shortening the copy. |
| Page content | `LibraryProfileLanguageSettingsSections` replaces `LibraryProfileLanguageSettingsRow`. It has two cards. *Anime Info Language* has a Follow System toggle, with a segmented picker when the toggle is off. *Default Poster* has two selectable rows, each with a one-line note on what it falls back to and a checkmark on the current choice. The full-width rows replace the menu capsule, so the short capsule labels ("Original Language" / "Anime Info Language") were removed. |
| Toggle animation | The Follow System toggle and segmented picker stay. On the pushed page, the toggle binding's `withAnimation` never reached the destination, so the picker appeared instantly and the poster card jumped. `LibraryProfileLanguageSettingsSections` now puts both cards in one stack with `.animation(_:value: followsSystemLanguage)`. Onboarding animates its own stack on the same value, and the hub/workspace already did. The settings view now uses a single `onChange` on the resolved language instead of two handlers; the behavior is the same. Rejected: making Follow System a fourth checkmark row (tried briefly; the maintainer wants the picker). |
| Onboarding | The language step shows the same two cards under its message. Previously it showed the hub row inside a setup panel. |
| Japanese copy | "Default Poster" is now 既定のポスター. The notes are now なければアニメ情報の言語を使用 / なければ原語を使用, and the zh notes are shortened to match. The refresh alert uses 既定のポスター. |
| Guides | `docs/anishelf_overview*.md` step 10 now lists six groups and describes Default Poster. The `../anishelf-site` guides (en/zh/ja) now point to Settings › Language and add a Default Poster paragraph. |

## Refs

- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfilePreferenceSections.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsHub.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsView.swift`
- `MyAnimeList/Sources/Models/Library/LibraryProfileSettingsModels.swift`
- `MyAnimeList/Sources/Views/Gadgets/TMDbAPIOnboardingView.swift`
- Validation: `make build` succeeded and `swift format lint` is clean on the changed
  files. The maintainer is checking the UI.
