# 016 — Settings hub: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-13 |
| Origin | Samuel approved the Codex/Claude discussion and HTML settings plan before implementation. |
| Related | [Adaptive library](../005-adaptive-library/000-plan.md), [Multi-window presentation](../008-multi-window-presentation/000-plan.md) |

## Background

The profile overlay places eight expanded settings sections below the dashboard.
This creates excessive scrolling on iPhone. The approved discussion preserves the
profile identity while moving controls into focused pages. These are current
user-approved decisions, not reconstructed implementation rationale.

## Goals

- Keep the hero, 2×2 statistics, and Library Details on the hub. (Corrected
  2026-10-13: the approved plan moved Library Details behind the hero into a
  Library Overview page; Samuel reversed that after review. See 002.)
- Replace expanded settings with six destinations: language, library/tracking,
  appearance/interaction, airing/reminders, metadata/images, sync/data.
- Use one stable NavigationStack and flat root-owned path on all sizes. Only the
  hub changes to two columns at regular width and non-accessibility Dynamic Type.
- Keep TMDb inline in metadata/images and iCloud first in sync/data. Preserve
  every existing control, side effect, preference key/default, modal sizing,
  scene-aware action, and the LibraryView overlay's close callback.
- Show live language, reminder and sync status, including unresolved sync issues.

## Design / approach

Retire LibraryProfileSettingsCard and workspaceGrid. Split existing preference
and interface sections by purpose. Proposed new source files are
LibraryProfileSettingsHub.swift, LibraryProfileSettingsPages.swift, and
LibraryProfileCloudSyncController.swift under
MyAnimeList/Sources/Views/Library/LibraryProfileSettings/.

The root owns navigation, reveal state, language observation, existing operation
alerts/importer/sheets, and cloud action/conflict coordination. Conflicts remain
pending while another modal is active. Pages receive bindings and action closures;
LibraryProfileSettingsActions is not introduced into the environment. Local
control modals remain local. While a conflict is pending, the root checks the
actual scene presentation hierarchy as well as its SwiftUI presentation state;
this also covers UIKit share sheets without changing their public APIs.

Move reminder reload on appearance/foreground to the root, with a transient loaded
flag. Extract sync issue derivation for both the hub and sync section. Preserve
scoring, remembered-sharing and TMDb relay handlers alongside their toggles.
Use localized resources and translate new catalog entries.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Keep hero/stat grid | Preserves profile identity; a single summary row hid glanceable statistics. |
| Push focused pages | Collapsible sections could recreate the original long page. |
| Flat destinations, inline TMDb/iCloud | Two-control child pages add navigation without useful structure. |
| Same stack on iPad | A sidebar inside the profile adds complexity; adaptive hub columns suffice. |
| Status-only trailing values | Sampled preferences such as single-tap mode arbitrarily represent broad groups. |
| Stable operation ownership | Popping or resizing must not discard conflicts or reset async guards. |

## Validation and acceptance criteria

Run make build, then targeted simulator tests for hub-column policy and distinct
shared summary/conflict logic, using only the already-booted iPhone 18 Pro. Run
make run-sim and visually inspect hub, one subpage, and Back. Run make
format and make lint. Record failures and unverified iPad/runtime scenarios in
001-action.md. Do not stage, commit, push, or boot another simulator.

## Amendments

- Updated 2026-10-13: Visual review — spectrum tints, Library Details restored to the hub, copy and guide fixes — see [002-visual-review.md](002-visual-review.md)
