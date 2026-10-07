# AniShelf - Developer Notes

## Workflow

- Use the Makefile for routine tasks: `make clean`, `make refresh-packages`, `make format`, `make lint`, `make build`, `make test-sim`, and `make run-sim`.
- Use `make test-sim` for broad simulator-based validation. Use `make run-sim` when validating app runtime or UI behavior rather than relying only on `make build`, unless the user explicitly asks for device-based verification.
- Use `make run-device` for build, install, and launch on a connected iPhone only when the user explicitly asks for device-based verification.
- Prefer the smallest relevant build or test command before broad verification.
- If the user asks to perform a change in a new worktree, create that worktree under ../AniShelf-worktrees/.
- Use the `write-ai-doc` skill for substantial features and decision-shaping fixes. Follow [`docs-ai/workflow.md`](docs-ai/workflow.md) and read [`docs-ai/README.md`](docs-ai/README.md) for existing topics before creating a new record.
- Write `000-plan.md` before implementation and reconcile `001-action.md` afterward. Record reasons and rejected alternatives that code alone would miss; distinguish recovered discussion memory, implementation inference, and verified evidence.
- Keep related follow-ups in the existing entry with a numbered amendment. Skip routine investigations, reviews, test reports, minor polish, and docs-only edits unless a durable record is requested.
- Keep public tutorials and images in `docs/`; internal design history, contracts, and runbooks belong in `docs-ai/`.
- OpenSpec is retired for this project; use `docs-ai/` records instead.

## Code Style

- When creating new source files, include the standard Xcode file comment header. Use the format below, attributing authorship to the agent (OpenAI Codex Or Claude Code) on behalf of the user (replace `<username>` with the actual GitHub username if known, otherwise use the user's name; use the real creation date in `YYYY/M/D` format):
  ```
  //
  //  FileName.swift
  //  AniShelf
  //
  //  Created by <agent> on behalf of <username> on YYYY/M/D.
  //
  ```
  Omit this header only when the user explicitly requests it.
- Keep edits aligned with existing project style.
- Use `LocalizedStringResource` whenever possible for user-facing SwiftUI strings, including labels, helper text, and accessibility copy.

## Testing

- Unit tests live in `MyAnimeList/Tests/` and `DataProvider/Tests/`.
- Use `make test` only when the user explicitly asks for physical-device testing or there is a specific device-only reason.
- To run only the relevant tests: for app tests, pass one or more whitespace-separated Xcode test identifiers with `APP_TEST_ONLY`, for example `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryMetadataRefreshTests'` or `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryExportManagerTests MyAnimeListTests/LibraryBackupRestoreTests'`. For DataProvider package tests, use Swift Testing's native filter syntax, for example `make test-dataprovider DATAPROVIDER_TEST_FILTER='LibrarySyncTests'` or `make test-dataprovider DATAPROVIDER_TEST_FILTER='LibrarySyncTests|MigrationTests'`. Only run the full suite when there is a good reason.
- Do not create excessive or redundant tests. Add only the smallest set that protects distinct behavior, prefer extending existing tests, and avoid duplicating coverage across layers. Simple wiring, copy, or layout changes may need no new tests.
- If a simulator is already booted, use it for install/testing as appropriate. Do not boot a simulator without explicit user permission, even when tests require one.

## Commits

- Use jj (colocated with Git) for local version control: `jj describe`, `jj new`, and `jj log` instead of `git add` and `git commit`. Record your own work proactively with `jj describe` and `jj new`, even when the user does not explicitly request a commit; do not squash, rebase, abandon, or edit changes you did not create in the current task without asking. Moving bookmarks, `jj git push`, and `--ignore-immutable` still require explicit authorization.
- Use conventional commits: `<type>: <subject>`.
- Write imperative, capitalized subjects; keep them concise and avoid periods.
- Add a body when the change needs explanation.
- Organize complex work into coherent changes.

## Releases

- Use the project-specific [`anishelf-release`](.codex/skills/anishelf-release/SKILL.md) skill for every source-control release. The skill ends at verified Git publication; the maintainer handles post-push app distribution.

## Additional Notes

- Use `@ViewBuilder` wisely. Do not simply add `return` to resolve compiler warnings.
- Do not condition ordinary SwiftUI animations on `accessibilityReduceMotion` by default. Treat Reduce Motion as a targeted response to substantial spatial or continuous motion, not as a blanket switch that disables animation. Add Reduce Motion-specific behavior only when the use case strongly calls for it and after explicit user confirmation.
- For new SwiftData migrations, keep `MigrationPlan.swift` focused on orchestration and migration policy. Put source-side field extraction on the old schema models via helpers like `migrationDTO()`, and put target-side rebuild logic on the new schema models via version-specific initializers or bridge helpers.
- When adjacent schema versions mostly share the same entry payload, prefer shared plain DTO bridges such as `AnimeEntryMigrationDTO` and `AnimeEntryDetailDTO` instead of re-copying field lists in `MigrationPlan.swift`. Treat those DTOs as transient migration/fetch bridges, not persisted SwiftData model types.
- During SwiftData schema version bumps, qualify versioned model references inside older schema helper/bridge files, for example `SchemaV2_7_3.AnimeEntrySeasonSummary` instead of bare `AnimeEntrySeasonSummary`. Once `CurrentSchema` advances, unqualified names in older versioned files can resolve to the new schema types and break the build.
- When you change/add user-facing text, update the localization files.

## Website Maintenance

- When screenshots or user-facing feature names change, update `../anishelf-site` to match. The site uses `.app-store-assets/screenshots/` and follows `MyAnimeList/Resources/Localizable.xcstrings`.
