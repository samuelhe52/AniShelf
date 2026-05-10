# AniShelf - Developer Notes

## Workflow

- Use the Makefile for routine tasks: `make clean`, `make refresh-packages`, `make format`, `make lint`, `make build` and `make test`.
- Use `make run-device` for build, install, and launch on a connected iPhone.
- If visual feedback is needed, run `make run-device`, then use Computer Use to open iPhone Mirroring or Quicktime and inspect the launched app there. Default to Quicktime, unless the user dictates otherwise.
- Prefer the smallest relevant build or test command before broad verification.
- If the user asks to perform a change in a new worktree, create that worktree under ../AniShelf-worktrees/.

## Code Style

- Follow `swift-format` and keep edits aligned with existing project style.
- Use `LocalizedStringResource` whenever possible for user-facing SwiftUI strings, including labels, helper text, and accessibility copy.

## Testing

- Unit tests live in `MyAnimeList/Tests/` and `DataProvider/Tests/`.
- Run tests with `make test`. Do not attempt to run tests with custom commands unless you have a specific reason to do so. Even if you do use custom commands, ensure that you run tests on a connected physical device instead of on a simulator.
- Add or update tests with behavior changes when practical.

## Commits

- Use conventional commits: `<type>: <subject>`.
- Write imperative, capitalized subjects; keep them concise and avoid periods.
- Add a body when the change needs explanation.

## Additional Notes

- Use `@ViewBuilder` wisely. Do not simply add `return` to resolve compiler warnings.
- For new SwiftData migrations, keep `MigrationPlan.swift` focused on orchestration and migration policy. Put source-side field extraction on the old schema models via helpers like `migrationDTO()`, and put target-side rebuild logic on the new schema models via version-specific initializers or bridge helpers.
- When adjacent schema versions mostly share the same entry payload, prefer shared plain DTO bridges such as `AnimeEntryMigrationDTO` and `AnimeEntryDetailDTO` instead of re-copying field lists in `MigrationPlan.swift`. Treat those DTOs as transient migration/fetch bridges, not persisted SwiftData model types.
- During SwiftData schema version bumps, qualify versioned model references inside older schema helper/bridge files, for example `SchemaV2_7_3.AnimeEntrySeasonSummary` instead of bare `AnimeEntrySeasonSummary`. Once `CurrentSchema` advances, unqualified names in older versioned files can resolve to the new schema types and break the build.
