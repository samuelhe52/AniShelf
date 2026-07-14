# AniShelf - Developer Notes

## Workflow

- Use the Makefile for routine tasks: `make clean`, `make refresh-packages`, `make format`, `make lint`, `make build`, `make test-sim`, and `make run-sim`.
- Prefer `make test-sim` and `make run-sim` for validation unless the user explicitly asks for device-based verification.
- Use `make run-device` for build, install, and launch on a connected iPhone only when the user explicitly asks for device-based verification.
- If visual feedback is needed for a device run, use `make run-device`, then use Computer Use to open iPhone Mirroring or Quicktime and inspect the launched app there. Default to Quicktime, unless the user dictates otherwise.
- Prefer the smallest relevant build or test command before broad verification.
- If the user asks to perform a change in a new worktree, create that worktree under ../AniShelf-worktrees/.

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
- Follow `swift-format` and keep edits aligned with existing project style.
- Use `LocalizedStringResource` whenever possible for user-facing SwiftUI strings, including labels, helper text, and accessibility copy.

## Testing

- Unit tests live in `MyAnimeList/Tests/` and `DataProvider/Tests/`.
- Run tests with `make test-sim` by default. Use `make test` only when the user explicitly asks for physical-device testing or there is a specific device-only reason.
- When developing new features or adding tests, run only the relevant tests first. For app tests, pass one or more whitespace-separated Xcode test identifiers with `APP_TEST_ONLY`, for example `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryMetadataRefreshTests'` or `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryExportManagerTests MyAnimeListTests/LibraryBackupRestoreTests'`. For DataProvider package tests, use Swift Testing's native filter syntax, for example `make test-dataprovider DATAPROVIDER_TEST_FILTER='LibrarySyncTests'` or `make test-dataprovider DATAPROVIDER_TEST_FILTER='LibrarySyncTests|MigrationTests'`. Only run the full suite when there is a good reason.
- Add or update tests with behavior changes when practical.

## Commits

- Use conventional commits: `<type>: <subject>`.
- Write imperative, capitalized subjects; keep them concise and avoid periods.
- Add a body when the change needs explanation.
- For long-running, complex tasks, or when the task can be split into several subtasks cleanly, make coherent checkpoint commits along the way instead of waiting until the entire task is complete.

## Additional Notes

- Use `@ViewBuilder` wisely. Do not simply add `return` to resolve compiler warnings.
- For new SwiftData migrations, keep `MigrationPlan.swift` focused on orchestration and migration policy. Put source-side field extraction on the old schema models via helpers like `migrationDTO()`, and put target-side rebuild logic on the new schema models via version-specific initializers or bridge helpers.
- When adjacent schema versions mostly share the same entry payload, prefer shared plain DTO bridges such as `AnimeEntryMigrationDTO` and `AnimeEntryDetailDTO` instead of re-copying field lists in `MigrationPlan.swift`. Treat those DTOs as transient migration/fetch bridges, not persisted SwiftData model types.
- During SwiftData schema version bumps, qualify versioned model references inside older schema helper/bridge files, for example `SchemaV2_7_3.AnimeEntrySeasonSummary` instead of bare `AnimeEntrySeasonSummary`. Once `CurrentSchema` advances, unqualified names in older versioned files can resolve to the new schema types and break the build.
