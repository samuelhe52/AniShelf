# AniShelf design and decision records

This directory records why AniShelf is built this way and what actually shipped.
Use the [workflow](workflow.md) for substantial new features and decision-shaping
fixes. Ordinary tasks do not need numbered documentation.

## Index

Entries 001–012 and 014 were backfilled on 2026-10-07: their plans are
retrospective, and their action records were assembled from source and local Git
history without running tests or runtime checks. For those entries, Implemented
means the recorded scope is present in the inspected source, not that every
historical runtime scenario was rerun. Entry 010 remains an unimplemented proposal.

| ID | Anchor date | Topic / plan | Status | Outcome |
| --- | --- | --- | --- | --- |
| 001 | 2026-05-30 | [Selective library sync](001-selective-library-sync/000-plan.md) | Implemented (retrospective) | [Action](001-selective-library-sync/001-action.md) |
| 002 | 2026-06-13 | [Image-path storage and bounded rendering](002-image-path-storage/000-plan.md) | Implemented (retrospective) | [Action](002-image-path-storage/001-action.md) |
| 003 | 2026-06-19 | [Persistent-store recovery](003-persistent-store-recovery/000-plan.md) | Implemented (retrospective) | [Action](003-persistent-store-recovery/001-action.md) |
| 004 | 2026-07-11 | [Respectful review prompts](004-respectful-review-prompts/000-plan.md) | Implemented (retrospective) | [Action](004-respectful-review-prompts/001-action.md) |
| 005 | 2026-07-13 | [Adaptive library and detail ownership](005-adaptive-library/000-plan.md) | Implemented (retrospective) | [Action](005-adaptive-library/001-action.md) |
| 006 | 2026-08-09 | [Broadcast resolution and device-local reminders](006-broadcast-and-reminders/000-plan.md) | Implemented (retrospective) | [Action](006-broadcast-and-reminders/001-action.md) |
| 007 | 2026-08-25 | [Background sync suspension safety](007-background-sync-safety/000-plan.md) | Implemented (retrospective) | [Action](007-background-sync-safety/001-action.md) |
| 008 | 2026-09-27 | [Multi-window presentation](008-multi-window-presentation/000-plan.md) | Implemented (retrospective) | [Action](008-multi-window-presentation/001-action.md) |
| 009 | 2026-09-27 | [Cloud sync convergence and partial failures](009-cloud-sync-correctness/000-plan.md) | Implemented (retrospective) | [Action](009-cloud-sync-correctness/001-action.md) |
| 010 | 2026-09-27 | [Reusable selective sync package](010-selective-sync-package/000-plan.md) | Planned | — |
| 011 | 2026-09-28 | [Parent-preserving library deletion](011-parent-preserving-deletion/000-plan.md) | Implemented (retrospective) | [Action](011-parent-preserving-deletion/001-action.md) |
| 012 | 2026-10-03 | [Rewatch tracking and clocked progress resets](012-rewatch-tracking/000-plan.md) | Implemented (retrospective) | [Action](012-rewatch-tracking/001-action.md) |
| 013 | 2026-10-07 | [Curated decision records](013-documentation-workflow/000-plan.md) | Implemented | [Action](013-documentation-workflow/001-action.md) |
| 014 | 2026-06-20 | [Library multi-selection rendering invariants](014-multiselect-invariants/000-plan.md) | Implemented (retrospective) | [Action](014-multiselect-invariants/001-action.md) |
| 015 | 2026-10-13 | [Library categories](015-library-categories/000-plan.md) | Implemented | [Action](015-library-categories/001-action.md), [optional sticky strip](015-library-categories/002-sticky-category-strip.md), [interactive reordering](015-library-categories/003-interactive-tab-reordering.md) |
| 016 | 2026-10-13 | [Settings hub](016-settings-hub/000-plan.md) | Implemented | [Action](016-settings-hub/001-action.md), [visual review](016-settings-hub/002-visual-review.md), [inline language](016-settings-hub/003-inline-language.md), [section palette](016-settings-hub/004-section-palette.md), [iPad workspace](016-settings-hub/005-ipad-workspace.md), [palette strength](016-settings-hub/006-palette-strength.md) |
| 017 | 2026-10-14 | [CloudKit zone lifecycle and account errors](017-cloud-zone-lifecycle/000-plan.md) | Implemented | [Action](017-cloud-zone-lifecycle/001-action.md) |
| 018 | 2026-10-15 | [Default poster language and onboarding language step](018-poster-language/000-plan.md) | Implemented | [Action](018-poster-language/001-action.md), [language page](018-poster-language/002-language-page.md) |
| 020 | 2026-10-15 | [Native macOS feasibility and migration options](020-native-macos/000-plan.md) | In progress (native target implementation) | [002](020-native-macos/002-implementation-decisions.md), [slice 1](020-native-macos/003-slice-1-native-build.md) |

## Find a contract or source

- [Adaptive library requirements](005-adaptive-library/requirements/adaptive-library-experience/spec.md).
- [Adaptive modal requirements](005-adaptive-library/requirements/adaptive-modal-presentations/spec.md).
- [Recovery requirements](003-persistent-store-recovery/historical/specs/persistent-store-recovery/spec.md).
- [Known legacy schema bridge](003-persistent-store-recovery/002-legacy-schema-bridge.md).
- [Why shipped schema versions must never change in place](003-persistent-store-recovery/003-v279-schema-collision.md).
- [Broadcast availability policy](006-broadcast-and-reminders/broadcast-availability-policy.md).
- [Why reminders use individual occurrences](006-broadcast-and-reminders/recurring-notifications-rationale.md).
- [Reusable sync package design and pending stages](010-selective-sync-package/design.md).
- [Migration inventory and provenance](013-documentation-workflow/migration-inventory.md).

## Read historical sources carefully

The retained requirements are behavioral references; editing them needs no special
CLI. `historical/` attachments preserve older source documents, findings, and task
lists. Their original dates and statuses remain intact, except for relocated Markdown
links. A parent action record explains later changes and known differences.

Source inspection establishes implemented structure. Memory can recover motives
but is identified as recollection; it is not substituted for runtime observation.
Historical test reports are preserved as reports, not claimed as tests run today.

Public tutorials and images remain under `docs/`; root READMEs and privacy policy
retain their public paths. Operational asset READMEs remain with their packages.
