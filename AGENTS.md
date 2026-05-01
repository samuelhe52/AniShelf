# AniShelf - Developer Notes

## Workflow

- Use the Makefile for routine tasks: `make clean`, `make refresh-packages`, `make format`, `make lint`.
- Use the Makefile target for real-device validation: `make run-device` for build, install, and launch on a connected iPhone.
- Prefer the smallest relevant build or test command before broad verification.

## Code Style

- Follow `swift-format` and keep edits aligned with existing project style.
- Use `LocalizedStringResource` whenever possible for user-facing SwiftUI strings, including labels, helper text, and accessibility copy.

## Testing

- Unit tests live in `MyAnimeList/Tests/` and `DataProvider/Tests/`.
- Add or update tests with behavior changes when practical.

## Commits

- Use conventional commits: `<type>: <subject>`.
- Write imperative, capitalized subjects; keep them concise and avoid periods.
- Add a body when the change needs explanation.
