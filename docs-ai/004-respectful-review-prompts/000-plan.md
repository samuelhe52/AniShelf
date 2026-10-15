# 004 — Respectful review prompts: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-07-11 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Multi-window presentation](../008-multi-window-presentation/000-plan.md) |

## Background

The maintainer requested a lightweight review policy that waits for meaningful
completed actions. The goal was to avoid startup interruptions and a custom rating
flow while still giving satisfied returning users a chance to leave a review.

## Goals

- Use the system review request from settled success flows.
- Keep eligibility small and deterministic.
- Persist the local engagement cycle without a new analytics subsystem.

## Design / approach

`AppReviewPromptController` records a small set of successful engagement actions
in UserDefaults. The app host waits two seconds, rechecks eligibility and visible
activity, and invokes the system request. The current local thresholds are seven
days since first launch, five active days, eight points, three actions, and a
90-day cooldown after an attempt.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Successful-flow trigger | Launch or foreground alone says little about whether a user has completed something useful. |
| System review API, no custom rating dialog | The maintainer explicitly excluded a custom prompt and wanted the system to handle its own presentation limits. |
| Two-second settling delay | Chosen in discussion to allow the successful flow to settle without adding a long scheduled interruption. |
| Simple local cooldown and small action set | The maintainer rejected unnecessary extra caps and instrumentation of trivial interactions. |

## Evidence and recovered rationale

The motivation and rejected extra complexity were recovered from prior-discussion
memory. The thresholds and two-second delay were checked in the current controller
and app host. This records AniShelf's policy; it does not assert a current external
StoreKit quota or promise that a system prompt will be shown.

## Validation and acceptance criteria

Use deterministic clock/defaults tests for eligibility, duplicate credit, and
cycle reset. Runtime validation should exercise a settled flow; a request attempt
must not be treated as a displayed prompt.

## Amendments

None yet.
