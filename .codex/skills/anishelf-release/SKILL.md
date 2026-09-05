---
name: anishelf-release
description: Prepare and publish AniShelf source-control releases through validation, release commits, annotated tags, and the main-to-release pull request. Use for AniShelf release preparation, readiness checks, or continuing an approved release flow. Ends at verified Git publication; excludes app distribution after push.
---

# AniShelf release

Use this skill for AniShelf's source-control release workflow. Read the repository's `AGENTS.md` for project conventions and validation constraints. Resolve the paths below from the repository root.

The scope deliberately ends with the merged `release` branch and published Git tag. Xcode archive/upload, TestFlight rollout, App Store Connect submission, and other app-distribution procedures are handled by the maintainer outside this skill. Do not treat their absence as a release-workflow defect or claim that Git publication means the app has shipped.

For a readiness check or workflow explanation, inspect and report only. For a release-preparation request, complete the requested local preparation and validation before presenting the next approval gate. Resume from verified current state without repeating completed steps. Preserve unrelated working-tree changes throughout.

## Prepare and validate

1. Inspect the working tree, branch state, and existing release tags. Start release work from an up-to-date `main` and review all changes since the latest applicable release tag. Confirm the intended version and tag before changing version metadata.
2. Prepare the release metadata together:
   - Update the app version in `MyAnimeList.xcodeproj/project.pbxproj`; check both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the app's build configurations. Do not assume the build number should carry forward or change unrelated test-target versions.
   - Confirm an appropriate entry for the target version in `MyAnimeList/Sources/Models/WhatsNewModels.swift`.
   - Update affected translations in `MyAnimeList/Resources/Localizable.xcstrings` and check the localization catalogs for missing translations. String catalogs are JSON; `jq empty` checks syntax, not translation completeness.
3. Check whether `README.md`, `README.zh-CN.md`, and `docs/anishelf_overview.md` need release-related changes. Update these documents only with explicit user permission.
4. Use the Makefile for formatting, linting, relevant tests, and a Release build: `make format`, `make lint`, and `make build CONFIGURATION=Release`. Review formatting changes to keep unrelated edits out of the release.
5. Run the smallest relevant tests first, using `APP_TEST_ONLY` or `DATAPROVIDER_TEST_FILTER` as documented in `AGENTS.md`. Use `make test-sim` when broad validation is warranted and `make run-sim` for runtime or UI validation. Reuse an already booted simulator; obtain explicit permission before booting one or performing physical-device validation.
6. Review the resulting diff and run `git diff --check`. Report the checks actually completed and any remaining validation gaps before committing.

## Approval gates

Each commit, tag creation, branch push, PR creation, PR merge, and tag push is a separate human-approval gate. Follow the user's explicit authorization for the action; do not request the same authorization again while it remains unconsumed.

Before a gate that has not been authorized, state the single next action and its immediate local or remote effects, then ask for approval in the conversation. Approval is consumed when that action is performed and does not carry into another step. Broad instructions such as "proceed with the release workflow," "proceed," or "continue" are not blanket approval. A direct affirmative reply to a precisely scoped request authorizes only that requested action. Resolve ambiguous approval before performing the action.

After completing a gate, report its result and request fresh approval before the next unauthorized gate. Creating or editing a PR, committing review fixes, and pushing those fixes remain subject to the same authorization boundaries. Invoking this skill does not itself authorize any of these operations.

## Publish source control

1. With approval, create the preflight commit containing release preparation other than the Xcode project version change. This changes local Git history only.
2. With fresh approval, create the release commit containing the version change. This changes local Git history only. Combine the two commits as one gated action only when the user explicitly requests a combined commit.
3. With fresh approval, create and verify the annotated `vX.Y` tag on the release commit, using the agreed version's actual tag name. This creates a local tag and does not authorize publishing it.
4. With fresh approval, push `main`. This updates the remote `main` branch and does not authorize opening a pull request.
5. With fresh approval, open the `main` to `release` pull request. This creates a remote pull request and does not authorize merging it.
6. Start an independent reviewer subagent to review the exact pull request diff without modifying it. Give the reviewer the PR's base and head commit IDs so the review covers a specific revision.
7. Address review findings and rerun affected validation. Obtain the required approval for any resulting commits or remote updates. If the PR changes after review, have the reviewer check the updated diff. Before continuing, verify that the intended release tag targets the agreed release revision; do not move or replace an existing tag without explicit authorization.
8. With fresh approval, merge the pull request without squash or rebase so the tagged release commit is preserved. Verify that the tagged commit is reachable from the merged remote `release` branch. This merge does not authorize publishing the release tag.
9. With fresh approval, push the release tag explicitly. Verify that the remote tag resolves to the intended commit.

Report the release version, commit, PR and merge result, published tag, and completed validation. Identify any unfinished authorized work precisely. Once Git publication is verified, hand off to the maintainer for the post-push app-distribution procedure.
