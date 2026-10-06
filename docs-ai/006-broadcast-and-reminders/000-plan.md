# 006 — Broadcast resolution and device-local reminders: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-08-09 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Adaptive detail session](../005-adaptive-library/000-plan.md) · [Multi-window routing](../008-multi-window-presentation/000-plan.md) |

## Background

TMDb provides AniShelf's identities and date-level airing evidence but not all
exact episode instants. TVMaze supplies broadcast scheduling, with incomplete ID
bridges and provider numbering that may differ from TMDb.

## Goals

- Resolve eligible series on demand without persisting provider payloads.
- Require confirmation before saving title-based identity guesses.
- Use exact verified next-episode instants for device-local reminders.
- Keep broadcast failure independent of ordinary metadata and detail loading.

## Design / approach

Use live TMDb scheduling plus external IDs in one request, then TVDB/IMDb lookup
and TVMaze show hydration. `EntryDetailBroadcastModel` belongs to the stable detail
session. Save confirmed identity mappings only. The reminder manager persists
subscription intent in device-local UserDefaults and schedules at most one verified
next-episode request per subscription. See the [availability policy](broadcast-availability-policy.md),
[recurrence rationale](recurring-notifications-rationale.md), and [original feature plan](historical/broadcast-time-feature-plan.md).

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| TMDb-to-TVDB/IMDb bridge | AniShelf stores TMDb identity; a provider without a usable bridge cannot resolve the existing library automatically. |
| User confirmation for title fallback | An ID miss can be a bridge gap, not show absence. Fuzzy title search alone is insufficient evidence to persist a match. |
| Transient schedules, durable confirmed IDs | Provider airtimes change. Persisting schedule snapshots in SwiftData or syncing them would confuse fresh provider facts with user intent. |
| Calendar components for TMDb dates | Treating a date-only air date as UTC midnight shifts it to another day in some device zones. |
| One nonrepeating verified episode | An indefinite weekly trigger cannot represent skipped weeks or correction of an individual episode. The maintainer explicitly limited scope to the embedded next episode. |
| Device-local intent, best-effort refresh | Chosen over synchronized subscriptions or a guaranteed background schedule; notification permission and delivery are device concerns. |

## Evidence and recovered rationale

The original feature plan records resolver ownership, confirmation, and provider
comparison rules. Prior-discussion memory adds the explicit device-local/best-effort
choice and the scope limit against fetching the full episode list. Current reminder
code is named `AiringReminderManager`; it replaced the older episode-notification
implementation mentioned in prior discussions in `b479653`. No old provider coverage counts are presented as current.

## Validation and acceptance criteria

Check confirmed mapping versus transient candidates, negative-offset date-only
cases, session migration, exact nonrepeating requests, targeted cancellation,
request limits, and preserved subscription intent after provider failure.
Refresh opportunities are best effort; static tests do not prove system delivery.

## Amendments

None yet.
