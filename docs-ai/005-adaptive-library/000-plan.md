# 005 — Adaptive library and detail ownership: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-07-13 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Broadcast session state](../006-broadcast-and-reminders/000-plan.md) |

## Background

The phone-oriented library needed to use resizable windows without converting
Gallery, List, and Grid into permanently constrained navigation columns. Phone
sheet appearance and active detail work were compatibility requirements.

## Goals

- Keep each browsing mode full-canvas when detail is closed.
- Use genuine sheets in compact size class and inspectors in regular size class.
- Preserve canonical detail session and selection through host changes.
- Adapt Gallery by content fit, independently of detail-host policy.

## Design / approach

Retain the [full original design](historical/design.md) and the two requirement
references under `requirements/`. Host policy reads root horizontal size class;
Gallery uses its own geometry policy. `EntryDetailSessionStore` owns the session
above both transient hosts. Root workflows take precedence, nested detail sheets
dismiss before migration, and stale host callbacks cannot clear incoming detail.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Dismissible inspector, full-canvas library | Permanent `NavigationSplitView` or a custom persistent column would constrain all browsing modes and change compact navigation behavior. |
| Genuine compact sheet | The original design records a same-build A/B comparison: inspector compact adaptation did not reproduce the established Liquid Glass surface. App material tweaks did not fix host semantics. |
| Discrete size-class host policy | Width remaining after an inspector opens must not feed back into host selection. Historical per-mode geometry thresholds were replaced, not retained as current rules. |
| One authoritative session owner | Broad `.id()` resets and child-owned sessions recreate detail work and cause flashes. Keep resets scoped to the document or controls that actually need them. |
| Repository/session persistence seams | The maintainer rejected passing `DataProvider` into `EntryDetailView`; low-level handlers can become stale after store reload. |

## Evidence and recovered rationale

The sheet comparison, navigation alternative, and migration rules are recorded
in the original design. Prior-discussion memory adds the rejected GeometryReader
experiment, the broad identity-reset failure, and the explicit request to keep
storage primitives out of the detail view. Code corroborates the current ownership.
The failed layout experiment is evidence for examining host semantics, not a rule
against all GeometryReaders.

## Validation and acceptance criteria

Preserve the original resize/current-phone matrix and completed 47-task list.
Check host generations, session identity, nested dismissal, and root-workflow dormancy.
Historical task completion is not fresh visual parity verification.

## Amendments

None yet.
