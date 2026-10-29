# AniShelf - Developer Notes

## Workflow

- Use Makefile targets for routine tasks (`make help` lists them).
- Run `make clean`, `make refresh-packages`, or `make format` only when the task needs it or the user asks. `make refresh-packages` deletes `Package.resolved`, so dependencies can move to newer versions; `make format` rewrites the whole repository. Format only the files you touched with `swift format -i <paths>`.
- Validate on the affected platform. For iOS, use `make test-sim` for broad simulator-based validation and `make run-sim` when validating runtime or UI behavior rather than relying only on `make build`. For native macOS, verify with `make build-mac`; launch with `make run-mac` only when the user asks. `make run-mac` loads an 800-entry fixture library by default, not the real library.
- Physical-device targets (`make run-device`, `make test`, `make test-app`, `make test-app-live-fetch`) run only when the user explicitly asks. If a check needs a device, explain why and ask.
- If the user asks to perform a change in a new worktree, create that worktree under .worktrees/ in the repository root.
- Use the `write-ai-doc` skill for substantial features and decision-shaping fixes, as defined in [`docs-ai/workflow.md`](docs-ai/workflow.md).

## Code Style

- When creating new Swift source files, include the standard Xcode file comment header. Attribute authorship to the agent (OpenAI Codex or Claude Code) on behalf of Samuel He, and use the real creation date in `YYYY/M/D` format:
  ```
  //
  //  FileName.swift
  //  AniShelf
  //
  //  Created by <agent> on behalf of Samuel He on YYYY/M/D.
  //
  ```
  Omit this header only when the user explicitly requests it.
- Pass plain string literals to SwiftUI APIs that already take a `LocalizedStringKey` (`Text`, `Button`, `Label`, `.help`, and similar); do not wrap them in `LocalizedStringResource`. Use `LocalizedStringResource` for user-facing strings held in properties, models, or enums, or passed to APIs that do not localize literals.

## Testing

- Prefer the smallest relevant build or test command; run the full suite only when there is a good reason. For app tests, pass whitespace-separated Xcode test identifiers with `APP_TEST_ONLY`, for example `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryMetadataRefreshTests'`. For DataProvider package tests, use Swift Testing's filter syntax (`|` separates names), for example `make test-dataprovider DATAPROVIDER_TEST_FILTER='LibrarySyncTests'`.
- Do not create excessive or redundant tests. Add only the smallest set that protects distinct behavior, prefer extending existing tests, and avoid duplicating coverage across layers. Simple wiring, copy, or layout changes may need no new tests.
- If a simulator is already booted, use it for install/testing as appropriate. Do not boot a simulator without explicit user permission, even when tests require one. If none is booted, run the checks that do not need one (such as `make build` or `make test-dataprovider`), report what did not run, and ask.

## Commits

- Commit only when the maintainer asks; pushing requires explicit authorization.
- Organize work into coherent commits. Fold review corrections and reverts into the unpushed commit they fix rather than stacking them; this is always allowed. Changing pushed history requires the user's confirmation. Otherwise, do not amend, rebase, reset, or rewrite commits you did not create in the current task without asking.
- Other agents may be editing the same working tree. Stage only changes within the commit's scope, by path (`git add <paths>`); never use `git add -A`, `git add .`, or `git commit -a`. When a file also holds unrelated edits (often `Localizable.xcstrings`), stage selectively with `git add -p` or ask, and review the full staged diff before committing.
- When splitting work across parallel agents, give each agent separate files.
- Use conventional commits: `<type>: <subject>`, with imperative, capitalized, concise subjects and no trailing period.

## Releases

- Use the project-specific [`anishelf-release`](.codex/skills/anishelf-release/SKILL.md) skill for every source-control release. The skill ends at verified Git publication; the maintainer handles post-push app distribution.

## Additional Notes

- Do not condition ordinary SwiftUI animations on `accessibilityReduceMotion` by default. Treat Reduce Motion as a targeted response to substantial spatial or continuous motion, not as a blanket switch that disables animation. Add Reduce Motion-specific behavior only when the use case strongly calls for it and after explicit user confirmation.
- For new SwiftData migrations, keep `MigrationPlan.swift` focused on orchestration and migration policy. Put source-side field extraction on the old schema models via helpers like `migrationDTO()`, and put target-side rebuild logic on the new schema models via version-specific initializers or bridge helpers.
- When adjacent schema versions mostly share the same entry payload, prefer shared plain DTO bridges such as `AnimeEntryMigrationDTO` and `AnimeEntryDetailDTO` instead of re-copying field lists in `MigrationPlan.swift`. Treat those DTOs as transient migration/fetch bridges, not persisted SwiftData model types.
- During SwiftData schema version bumps, qualify versioned model references inside older schema helper/bridge files, for example `SchemaV2_7_3.AnimeEntrySeasonSummary` instead of bare `AnimeEntrySeasonSummary`. Once `CurrentSchema` advances, unqualified names in older versioned files can resolve to the new schema types and break the build.
- When you change or add user-facing text, update `MyAnimeList/Resources/Localizable.xcstrings` with `ja` and `zh-Hans` translations. In those, write CJK text directly next to Latin letters, digits, and format placeholders without a space (`关于AniShelf`, `%lld件`); system typography adds the gap.

## Website Maintenance

- When screenshots or user-facing feature names change, report the follow-up needed in `../anishelf-site`. Edit that repository only when the task covers it, and commit or deploy it only when asked. The site copies screenshots from this repository's `.app-store-assets/screenshots/` into its `src/assets/screens/` (then `npm run og`) and takes its labels from `MyAnimeList/Resources/Localizable.xcstrings`.
