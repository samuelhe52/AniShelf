# 002 — Image-path storage and bounded rendering: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-06-13 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Documentation index](../README.md) |

## Background

Persisting complete image URLs couples stored metadata to a chosen rendition
and base URL. The V2.8.0 transition stores TMDb paths and resolves display URLs
at the network/rendering boundary while retaining compatibility with older clients.

## Goals

- Decouple stored image identity from display rendition.
- Preserve custom posters across existing CloudKit and Codable readers.
- Bound image decode work and keep expensive processing out of UI work.

## Design / approach

Use `TMDbImagePath` for path normalization, version-specific migration bridges
for old URL fields, and `TMDbImageURLResolver` for display URLs. Keep legacy
`customPosterURL` shims where old clients still consume them.
The two [historical reviews](historical/README.md) retain the individual findings,
including invalid/refuted findings and their original status.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Persist paths, resolve URLs when rendering | A model-level rendition choice would couple schema and cache identity to UI sizing. This rationale is inferred from the implemented separation, not recovered as a verbatim maintainer decision. |
| Keep legacy URL fields during transition | Old builds do not read the new path key; path-only writes would lose the custom poster choice. |
| Honor divergent legacy custom-poster URLs | A stale path can shadow a newer edit from an older client. Precedence must preserve cross-version edits rather than blindly favoring the new field. |
| Bound decode concurrency | Unbounded image variants create avoidable memory and executor pressure; faster fan-out is not automatically better. |

## Evidence and recovered rationale

Compatibility and concurrency reasons are stated in the retained reviews and
matching fix commits. The separation rationale above is explicitly identified as
an implementation inference. Historical review status was preserved, not re-audited.

## Validation and acceptance criteria

Check URL-to-path fixtures, legacy custom-poster interchange, bounded hero
renditions, and decode concurrency. Do not infer current defects from dated line
numbers in preserved reviews.

## Amendments

None yet.
