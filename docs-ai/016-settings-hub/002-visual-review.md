# 016.002 — Visual review

## Context

After the first delivery ([001-action.md](001-action.md)), Claude Code ran a
code-level UI review, and Samuel reviewed the iPhone simulator and a device the
same day (2026-10-13). The decisions below come from that review conversation.

## Change

| Choice | Decision and alternative |
| --- | --- |
| Library summary | Library Details stays on the hub, below the 2×2 statistics; the hero is not a link. Samuel: "we don't need to fold the library summary." The Library Overview page and `.overview` destination were removed. Regular width restores the original side-by-side statistics/details summary (`fillsSummaryHeight`). |
| Hub and page colors | One continuous hue spectrum in hub order (`LibraryProfileSettingsPalette.step(_:)`): teal, blue, indigo, violet, continuing into the App Info rows. Every card on a pushed page uses its destination's step; toggles inherit it through the `libraryProfilePageTint` environment value. Delete All Animes and Restore stay red. Rejected: unrelated per-section hues (mint, teal, purple, and orange on one page read as noise), neutral-only tiles, and a single accent color. Samuel chose distinct hues, then asked for them to form a spectrum. |
| Hub card headers | Both hub cards use `PopupSectionCard`, the original Settings card's title size and padding. A plain `Label` header was too large and too tight. The bottom card gained an "App Info" header. |
| Metadata & Images | The image toggles form one section. Prefetch Images, Check Metadata Cache Size, and Refresh Infos share one card with icon rows and dividers, like the former Maintenance card. This replaces a one-row Metadata section whose header repeated the row icon. |
| Rows among toggles | Change API Key and Rebuild iCloud Sync drop their icon tile and side inset (`showsIcon: false`, `horizontalPadding: 0`) so their text lines up with the toggles. Rebuild keeps the 0.52 opacity it had in Maintenance while disabled. |
| Hub rows | Rows stack in columns with inset dividers. Regular width splits the six destinations column-major (3 + 3) instead of a row-major grid. |

Code review also removed dead code from the retired workspace layout
(`LibraryProfileMaintenancePalette`) and stray blank lines.

### Copy and guide audit

Samuel asked for an audit of Codex's copy and docs.

- New translations now match existing app terms. In Chinese, "Airing & Reminders" and
  "Broadcast" use 播出, like 播出提醒. In Japanese, Library & Tracking uses 視聴管理, like the
  Tracking section, and Metadata & Images uses メタデータ. Defaults is 既定の設定 / 默认设置.
- No manual spaces between CJK and Latin text; native typography handles the gap
  (Samuel, 2026-10-13). Spaces added during the audit were reverted, and
  "Support AniShelf" (`支持AniShelf`) and its Japanese string lost theirs to match
  "About AniShelf". The existing Chinese "Library Details" translation (`详情`)
  became `资料库详情`.
  A follow-up removed every remaining manual space between CJK text and Latin
  letters, digits, or format placeholders in the Japanese and Chinese catalog
  entries (178 values; placeholders were masked so `%lld` stays intact).
- App tutorials list the six groups inside step 9, replacing a standalone
  "Settings now groups…" paragraph. Website guides use the corrected names and
  drop a path repeated in the bullet after "These controls are in Sync & Data".

## Validation

- `make build` passed after each change.
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryProfileSettingsLayoutPolicyTests MyAnimeListTests/LibraryProfileSettingsStateTests'`
  passed (5 tests).
- `make run-sim` installed each revision on the booted iPhone 18 Pro. Samuel
  reviewed the screens; Claude Code did not capture screenshots of the pushed pages.

## Open questions

- Chinese mixes 你 and 您. Deferred by Samuel (2026-10-13) to a later pass.
- iPad layout, dark mode, and accessibility sizes: verified by Samuel (2026-10-13).
