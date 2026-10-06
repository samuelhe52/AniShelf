# Documentation migration inventory

Assembled on 2026-10-07 from local revision `1b5b5d6` and the installed skill.
Original source files were read before removal. The [machine-readable manifest](migration-manifest.json)
records SHA-256 hashes and each Markdown-link relocation. All source content is retained;
only the still-planned package design also receives explicit later-fix annotations.
The source revision preserves its pre-migration form in Git. No commit is created by this migration.

## Source coverage

| Original location (historical) | New location | Treatment |
| --- | --- | --- |
| `docs/implemented/cloudkit-sync-implementation-plan.md` | [cloudkit-sync-implementation-plan.md](../001-selective-library-sync/historical/cloudkit-sync-implementation-plan.md) | Retained; byte-identical |
| `docs/implemented/cloudkit-sync-stages-1-5-review.md` | [cloudkit-sync-stages-1-5-review.md](../001-selective-library-sync/historical/cloudkit-sync-stages-1-5-review.md) | Retained; byte-identical |
| `docs/implemented/code-review-2026-06-13.md` | [code-review-2026-06-13.md](../002-image-path-storage/historical/code-review-2026-06-13.md) | Retained; byte-identical |
| `docs/implemented/code-review-2026-06-14.md` | [code-review-2026-06-14.md](../002-image-path-storage/historical/code-review-2026-06-14.md) | Retained; byte-identical |
| `docs/broadcast-time-feature/broadcast-time-feature-plan.md` | [broadcast-time-feature-plan.md](../006-broadcast-and-reminders/historical/broadcast-time-feature-plan.md) | Retained; byte-identical |
| `docs/broadcast-time-feature/broadcast-availability-policy.md` | [broadcast-availability-policy.md](../006-broadcast-and-reminders/broadcast-availability-policy.md) | Retained; byte-identical |
| `docs/broadcast-time-feature/ios-recurring-notifications-qa.md` | [recurring-notifications-rationale.md](../006-broadcast-and-reminders/recurring-notifications-rationale.md) | Retained; byte-identical |
| `docs/cloud-sync-correctness-fixes-plan.md` | [cloud-sync-correctness-fixes-plan.md](../009-cloud-sync-correctness/historical/cloud-sync-correctness-fixes-plan.md) | Retained; links relocated |
| `docs/selective-cloud-sync-library-plan.md` | [design.md](../010-selective-sync-package/design.md) | Retained; proposal prerequisites annotated |
| `openspec/config.yaml` | [legacy-workflow-config.yaml](historical/legacy-workflow-config.yaml) | Retained; byte-identical |
| `openspec/changes/recover-corrupted-store-with-diagnostic-export/.openspec.yaml` | [change-metadata.yaml](../003-persistent-store-recovery/historical/change-metadata.yaml) | Retained; byte-identical |
| `openspec/changes/recover-corrupted-store-with-diagnostic-export/design.md` | [design.md](../003-persistent-store-recovery/historical/design.md) | Retained; byte-identical |
| `openspec/changes/recover-corrupted-store-with-diagnostic-export/proposal.md` | [proposal.md](../003-persistent-store-recovery/historical/proposal.md) | Retained; byte-identical |
| `openspec/changes/recover-corrupted-store-with-diagnostic-export/specs/persistent-store-recovery/spec.md` | [spec.md](../003-persistent-store-recovery/historical/specs/persistent-store-recovery/spec.md) | Retained; byte-identical |
| `openspec/changes/recover-corrupted-store-with-diagnostic-export/tasks.md` | [tasks.md](../003-persistent-store-recovery/historical/tasks.md) | Retained; byte-identical |
| `openspec/changes/archive/2026-07-24-adapt-library-for-resizable-windows/.openspec.yaml` | [change-metadata.yaml](../005-adaptive-library/historical/change-metadata.yaml) | Retained; byte-identical |
| `openspec/changes/archive/2026-07-24-adapt-library-for-resizable-windows/design.md` | [design.md](../005-adaptive-library/historical/design.md) | Retained; byte-identical |
| `openspec/changes/archive/2026-07-24-adapt-library-for-resizable-windows/proposal.md` | [proposal.md](../005-adaptive-library/historical/proposal.md) | Retained; byte-identical |
| `openspec/changes/archive/2026-07-24-adapt-library-for-resizable-windows/specs/adaptive-library-experience/spec.md` | [spec.md](../005-adaptive-library/historical/specs/adaptive-library-experience/spec.md) | Retained; byte-identical |
| `openspec/changes/archive/2026-07-24-adapt-library-for-resizable-windows/specs/adaptive-modal-presentations/spec.md` | [spec.md](../005-adaptive-library/historical/specs/adaptive-modal-presentations/spec.md) | Retained; byte-identical |
| `openspec/changes/archive/2026-07-24-adapt-library-for-resizable-windows/tasks.md` | [tasks.md](../005-adaptive-library/historical/tasks.md) | Retained; byte-identical |
| `openspec/specs/adaptive-library-experience/spec.md` | [spec.md](../005-adaptive-library/requirements/adaptive-library-experience/spec.md) | Retained; byte-identical |
| `openspec/specs/adaptive-modal-presentations/spec.md` | [spec.md](../005-adaptive-library/requirements/adaptive-modal-presentations/spec.md) | Retained; byte-identical |

## Recovered decisions

Prior-discussion memory was searched for feature and architecture choices, then
compared with this checkout and local commit history. Recovered reasons are labeled
in each plan; implementation inference is separately labeled. No personal library,
crash bundle, credential, or raw session transcript is copied into the repository.

| Entry | Additional rationale recovered | Corroborating evidence |
| --- | --- | --- |
| 001 | Rich metadata stays local; earlier lean-store idea is superseded by explicit records | Implementation plan; local-only `DataProvider` configuration |
| 003 | A schema mismatch is not proof of corruption; frozen one-stage legacy bridge avoids duplicating the canonical tail | `ModelContainerLoader`, `5ac704f` |
| 004 | Small settled-action policy, two-second delay, no custom rating dialog or extra instrumentation | `AppReviewPromptController`, `cad7b84`, app host |
| 005 | Single session owner, narrow identity resets, repository boundaries instead of storage primitives in views | `EntryDetailSession`, `LibraryView` |
| 006 | Device-local, best-effort reminders; one verified next episode instead of whole-episode-list scope | `AiringReminderManager`, resolver and model |
| 007 | Request lifetime starts before the sync gate; detached hydration avoids canceled insertions | Coordinator source, `c53e994` |
| 008 | Shared persistence with scene-targeted presentation; tests do not establish two-window runtime behavior | September multi-window commit series |
| 009 | Simple neutral issue UI; operation timeout and cancellation must reach the underlying CloudKit await | `388e664`, operation wrapper |
| 010 | Publishable library boundary, package-owned metadata, explicitly failure-prone codec escape hatch | Existing proposal; recovered discussion summary |
| 011 | Hide a parent while a surviving season still uses its display metadata | `c3b3a39`, repository source comment |
| 012 | Editable rewatch count replaces unknown-count/Undo ideas; clocked zeros prevent progress resurrection | `b3cd028`, `d79926b`, recovered discussion summary |

## Uncertainties retained

- No historical two-device, two-window, resize, or notification-delivery run is represented as fresh validation.
- The original cloud plan references a scratch review absent from the input tree. Its contents were not invented.
- Historical reviews include rejected findings and dated open items. They are preserved as source evidence, not accepted wholesale.
- Deferred sync defects need current reconciliation. The package remains Planned and has no completion action record.

## Documents intentionally left in place

- `README.md`, `README.zh-CN.md`, and `PRIVACY_POLICY.md`: public project and policy documents.
- `docs/anishelf_overview.md`, `docs/anishelf_overview.en.md`, and `docs/images/`: public tutorials and their assets.
- `.app-store-assets/poster/README.md` and `.app-store-assets/promo-video-v151-v199/README.md`: package-local asset instructions.
- `AGENTS.md` and the source-control release skill: developer and release procedures.

## Tooling retirement

Source coverage passed before deletion. The original `openspec/` directory, moved
development documents, Claude OpenSpec skills, and OPSX commands were removed.
The maintainer subsequently removed the five Codex OpenSpec skills; their absence
was verified and the unrelated release skill remains.
The `write-ai-doc` skill is now project-owned; see [002](002-audit-and-skill-rewrite.md).
