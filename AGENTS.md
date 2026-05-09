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
