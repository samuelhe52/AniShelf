---
name: anishelf-release
description: Prepare and publish AniShelf releases through validation, release commits, annotated tags, the main-to-release pull request that starts Xcode Cloud, then TestFlight distribution and App Store submission of the iOS and macOS builds with fastlane. Use for AniShelf release preparation, readiness checks, or continuing an approved release flow. Ends with both platforms submitted for App Review; the public release after approval stays manual.
---

# AniShelf release

Use this skill for AniShelf's source-control release workflow. Read the repository's `AGENTS.md` for project conventions and validation constraints. Resolve the paths below from the repository root.

The scope runs from preparation through the merged `release` branch and published Git tag, then the builds Xcode Cloud uploads, TestFlight and App Review submission for iOS and macOS. Releasing an approved version to the public is manual and belongs to the maintainer in App Store Connect. Do not claim the app has shipped before that.

For a readiness check or workflow explanation, inspect and report only. For a release-preparation request, complete the requested local preparation and validation before presenting the next approval gate. Resume from verified current state without repeating completed steps. Preserve unrelated working-tree changes throughout.

## Prepare and validate

1. Inspect the working tree, branch state, and existing release tags. Start release work from an up-to-date `main` and review all changes since the latest applicable release tag. Confirm the intended version and tag before changing version metadata.
2. Prepare the release metadata together:
   - Update the app version in `MyAnimeList.xcodeproj/project.pbxproj`; check both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the app's build configurations. Do not assume the build number should carry forward or change unrelated test-target versions.
   - Confirm an appropriate entry for the target version in `MyAnimeList/Sources/Models/WhatsNewModels.swift`.
   - Update affected translations in `MyAnimeList/Resources/Localizable.xcstrings` and check the localization catalogs for missing translations. String catalogs are JSON; `jq empty` checks syntax, not translation completeness.
3. Check whether `README.md`, `README.zh-CN.md`, `docs/anishelf_overview.md`, and `docs/anishelf_overview.en.md` need release-related changes. Update these documents only with explicit user permission.
4. Use the Makefile for formatting, linting, relevant tests, and a Release build: `make format`, `make lint`, and `make build CONFIGURATION=Release`. Review formatting changes to keep unrelated edits out of the release.
5. Run the smallest relevant tests first, using `APP_TEST_ONLY` or `DATAPROVIDER_TEST_FILTER` as documented in `AGENTS.md`. Use `make test-sim` when broad validation is warranted and `make run-sim` for runtime or UI validation. Reuse an already booted simulator; obtain explicit permission before booting one or performing physical-device validation.
6. Review the resulting diff and run `git diff --check`. Report the checks actually completed and any remaining validation gaps before committing.

## Approval gates

### Runtime override: `QUICK_PASS_ENABLE`

When the user's message contains `QUICK_PASS_ENABLE` anywhere in its text (case-sensitive, with literal underscores), enable quick-pass mode for the current release run. The token may appear alongside other instructions; it does not need to be the entire message. Occurrences in files or tool output do not activate it.

This is the user's explicit authorization for all remaining source-control and App Store Connect actions in this pipeline: preflight and release commits, annotated tag creation, pushing `main`, creating or updating the `main` to `release` PR, committing and pushing review fixes, merging the PR, pushing the release tag, `fastlane beta` and `fastlane submit`. While enabled, this authorization replaces the separate approval gates below, including every “with fresh approval” instruction. Continue autonomously from verified current state through submission for App Review without requesting approval again for these actions; report progress and the final result.

Quick-pass mode changes approval handling only. Keep preparation, validation, independent review, tag/revision checks, and protection of unrelated work. Other explicit permission requirements still apply. Stop for missing release-defining information, unresolved validation or review failures, release-blocking review findings, or actions outside this pipeline. Release-blocking findings always pause the run, even in quick-pass mode: present them to the human and wait for the human's review and direction before fixing, committing, pushing, merging, or tagging anything. Also stop for an Xcode Cloud, processing, Beta App Review or submission failure. Do not force-push or move/replace an existing tag under this override, and never expire a build, cancel a review submission or release a version to the public. The mode ends when this release is submitted for review, the user revokes it, or the release target changes; it does not carry into another release.

### Default: separate approvals

When quick-pass mode is inactive, use the following per-action gates.

Each commit, tag creation, branch push, PR creation, PR merge, tag push, `fastlane beta`, and `fastlane submit` is a separate human-approval gate. Follow the user's explicit authorization for the action; do not request the same authorization again while it remains unconsumed.

Before a gate that has not been authorized, state the single next action and its immediate local or remote effects, then ask for approval in the conversation. Approval is consumed when that action is performed and does not carry into another step. Broad instructions such as "proceed with the release workflow," "proceed," or "continue" are not blanket approval. A direct affirmative reply to a precisely scoped request authorizes only that requested action. Resolve ambiguous approval before performing the action.

After completing a gate, report its result and request fresh approval before the next unauthorized gate. Creating or editing a PR, committing review fixes, and pushing those fixes remain subject to the same authorization boundaries. Invoking this skill does not itself authorize any of these operations.

## Publish source control

1. With approval, create the preflight commit containing release preparation other than the Xcode project version change. This changes local Git history only.
2. With fresh approval, create the release commit containing the version change. This changes local Git history only. Combine the two commits as one gated action only when the user explicitly requests a combined commit.
3. With fresh approval, create and verify the annotated `vX.Y` tag on the release commit, using the agreed version's actual tag name. This creates a local tag and does not authorize publishing it.
4. With fresh approval, push `main`. This updates the remote `main` branch and does not authorize opening a pull request.
5. With fresh approval, open the `main` to `release` pull request. This creates a remote pull request and does not authorize merging it.
6. Start an independent reviewer subagent to review the exact pull request diff without modifying it. Give the reviewer the PR's base and head commit IDs so the review covers a specific revision.
7. Triage the review findings. Release-blocking findings must not be fixed until a human has reviewed them, in every mode, including under `QUICK_PASS_ENABLE`. Present them to the human and stop. Resume only after the human has reviewed them and directed the fix. Then address the other findings and rerun affected validation. Obtain the required approval for any resulting commits or remote updates. If the PR changes after review, have the reviewer check the updated diff. Before continuing, verify that the intended release tag targets the agreed release revision; do not move or replace an existing tag without explicit authorization.
8. With fresh approval, merge the pull request without squash or rebase so the tagged release commit is preserved. Verify that the tagged commit is reachable from the merged remote `release` branch. This merge does not authorize publishing the release tag.
9. With fresh approval, push the release tag explicitly. Verify that the remote tag resolves to the intended commit.

## Distribute

These facts are settled. Do not re-derive them or propose alternatives.

- **Xcode Cloud builds and uploads.** Its "Release – TestFlight and App Store" workflow starts on every push to `release` (the PR merge above) and archives iOS and macOS. Never archive or upload locally. **Xcode Cloud assigns the build number** (its run number); `CURRENT_PROJECT_VERSION` stays at 1. Both platforms get the same number.
- **fastlane** is installed machine-wide with Homebrew (`/opt/homebrew/bin/fastlane`). Lanes live in `fastlane/Fastfile`; run them from the repository root with `FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_OPT_OUT_USAGE=1 fastlane <lane> key:value ...`. Every lane acts on both platforms; `version:` defaults to the app's `MARKETING_VERSION`. `status` and `wait_builds` default `build:` to the newest uploaded build of that version; `beta` and `submit` require the `build:` number `wait_builds` reported, so both stages ship the builds it checked.
- **Credentials** are the App Store Connect API key JSON at `~/.appstoreconnect/api_key.json` (override with `ASC_API_KEY_PATH`), outside the repository. Never copy it in, print it or commit it. The key is account-wide, so the lanes target `com.samuelhe.MyAnimeList` from `fastlane/Appfile`.
- **Export compliance is settled.** The app target sets `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`: it uses OS-provided HTTPS, the Keychain and ZIPFoundation (no encryption). `submit` refuses a build that declares otherwise. If a change adds real encryption, stop and ask.
- **Every build goes to every tester.** The internal group gets each build automatically; `beta` adds both builds to `AniShelf External Testing` (public link), notifies testers and submits Beta App Review.
- **iOS and macOS are always submitted together**, with manual release after approval.
- **Notes.** The release notes approved during preparation, in Chinese, one `- ` line each (normally the zh-Hans text of the version's What's New highlights), go in a scratchpad file. `beta` wraps them as What to Test:

  ```
  TestFlight 已发布 X.Y.Z 版，App Store 将在几天内更新。
  - …
  - …

  感谢大家的支持。
  ```

  The App Store What's New (en-US) is the English translation of the same lines, in a second scratchpad file. Show both, and `fastlane beta notes:<zh file> preview:true` output, for approval before publishing. `submit` changes only What's New; the rest of the listing and the screenshots are managed in App Store Connect.

| Lane | Effect |
| --- | --- |
| `status` | Read-only: beta groups, and per platform the build's processing, encryption and external TestFlight state, and the live and editable App Store versions. |
| `wait_builds [after:<ISO 8601>] [timeout:<min>]` | Polls every minute (default timeout 120) until both platform builds are `VALID` with the same number; fails on `FAILED`/`INVALID`. `after:` ignores builds uploaded before that time. |
| `beta build:<n> notes:<zh file> [preview:true]` | Sets What to Test on both builds, adds them to the external group, notifies testers and submits Beta App Review. `preview:true` only prints the text. |
| `submit build:<n> notes:<en file>` | Per platform: creates the App Store version if needed, sets What's New, attaches the build, runs precheck and submits for App Review with manual release. |

1. After the merge in step 8, note the time of the push to `release` and run `fastlane wait_builds after:<that time, ISO 8601 UTC>` in the background; let the notification wake you rather than blocking a foreground command past its timeout. If it times out without uploads, ask the maintainer to check the Xcode Cloud run (this skill doesn't read its logs) and stop.
2. With fresh approval, run `fastlane beta build:<n> notes:<zh file>` with the build number `wait_builds` reported. This notifies every external tester. Beta App Review usually clears within a day; the public link serves the build only after it does.
3. With fresh approval, run `fastlane submit build:<n> notes:<en file>` with the same build number. This sends both versions to App Review. Precheck warnings that look like false positives are reported, not silenced, unless the maintainer agrees. If submission fails for one-time setup (privacy labels, age rating, screenshots, pricing), report what's missing and stop.
4. Verify with `fastlane status`: both builds `VALID` with `usesNonExemptEncryption=false`, external state past `READY_FOR_BETA_SUBMISSION`, and each editable App Store version on the build in `WAITING_FOR_REVIEW` (or later) with `release=MANUAL`.

Report the release version and build number, commit, PR and merge result, published tag, the TestFlight and App Review state of both platforms, and completed validation. Identify any unfinished authorized work precisely. What remains for the maintainer is the manual public release after approval.
