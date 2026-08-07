# Release Workflow

Follow this workflow for every release. Preserve unrelated working-tree changes throughout.

## Prepare and Validate

1. Start from an up-to-date `main` and review all changes since the latest release tag.
2. Run the normal format and lint checks, relevant tests, and a Release build.
3. Check the localization catalogs for missing translations.
4. Confirm that the target version has an appropriate What's New entry and that the app version is updated correctly.
5. Check whether `README.md` and `docs/anishelf_overview.md` need changes. Update them only with explicit user permission.

## Permission Rules

Every action marked as requiring approval in this workflow is a separate human-approval gate.

Before each gate, state the single next action, describe its immediate local or remote effects, and ask for approval in the conversation. The request must cover only that action.

Approval is consumed when the action is performed and never carries into another step. Broad instructions such as “proceed with the release workflow,” “proceed,” or “continue” are not blanket approval. A direct affirmative reply to a precisely scoped request authorizes only that requested action. If approval is ambiguous, ask again.

After completing a gate, report the result and stop before the next gate to request fresh approval.

## Publish

1. With approval, create the preflight commit containing release preparation other than the Xcode project version change. This changes local Git history only.
2. With fresh approval, create the release commit containing the version change. This changes local Git history only. The two commits may be combined as one gated action only when the user explicitly requests a combined commit.
3. With fresh approval, create and verify the annotated `vX.Y` tag on the release commit. This creates a local tag and does not authorize publishing it.
4. With fresh approval, push `main`. This updates the remote `main` branch and does not authorize opening a pull request.
5. With fresh approval, open the `main` to `release` pull request. This creates a remote pull request and does not authorize merging it.
6. Start an independent reviewer subagent to review the exact pull request diff without modifying it.
7. Address review findings and rerun affected validation.
8. With fresh approval, merge the pull request without squash or rebase so the tagged release commit is preserved. This updates the remote `release` branch and does not authorize publishing the release tag.
9. With fresh approval, push the release tag. This publishes the tag to the remote.
