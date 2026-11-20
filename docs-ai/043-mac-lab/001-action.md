# 043 — AniShelf Lab on macOS: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-11-21 | Codex: Lab configuration and scheme, a Swift snapshot tool, a persistent working copy, and per-service `#if ANISHELF_LAB` isolation. | Never committed; replaced |
| 2026-11-21 | Codex: TMDb key moved into a Lab-only Keychain item ([002](002-lab-tmdb-keychain.md)); `LAB_LANG`. | Never committed; key change kept |
| 2026-11-21 | Claude Code: rewrote Lab as a throwaway copy per launch, on fixture mode and command-line build settings, with `scripts/lab.py`. Production changes went from about 30 files to 3. | `feat: Add AniShelf Lab for testing on a copy of the live library` |

## Outcome and current state (as of 2026-11-21)

As planned. `make run-lab` builds into `.build/lab`, so Lab's DerivedData stays apart
from `make run-mac`'s.

## Deviations from plan

- Lab leaves out the embedded screen saver (`EXCLUDED_SOURCE_FILE_NAMES`). With the
  app's bundle ID applied to every target, the saver would carry Lab's ID and could
  replace the live one if installed from Lab.
- Fixture mode means airing reminders never refresh, and screen saver publication
  fails without Pictures access. Broadcast airtimes and AI providers behave as in a
  normal Debug build, with Lab's own provider keys.
- Caches (posters, metadata) and Lab's Keychain items persist across runs.

## Validation

- Samuel ran `make run-lab` against his real library and confirmed the flow works.
- `make build-lab` and `make build-mac` pass. The Lab app has bundle ID
  `com.samuelhe.MyAnimeList.lab`, passes strict signature verification, and is entitled
  to the sandbox, network, and user-selected files only.
- On throwaway WAL-mode databases, `VACUUM INTO` over a read-only connection produced a
  consistent standalone copy both with a writer open and after it closed, worked on a
  path with a space, and could not write to the source.

## Open questions

- Lab registers the same document types as AniShelf, so Finder may offer it for
  `.mallib` files.
