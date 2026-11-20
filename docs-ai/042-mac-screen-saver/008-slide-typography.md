# 042.008 — Slide typography and text rendering

## Context

Samuel's review of Poster Focus and Backdrop on a real screen (2026-11-20): the
overview's last line was cut through with a floating ellipsis; titles broke into two
uneven lines (ヱヴァンゲリヲン新 / 劇場版：Q); some entries showed four genres whose
Japanese names already contain "・" (アクション・アドベンチャー), so they blurred into
the " · " separators; text sizes and gaps were scattered over six lines; the Backdrop
info line was too prominent. Claude rendered both layouts in-process at 1512×982,
3440×1440, and 982×1512 with real artwork and checked each change visually.

## Change

| Choice | Decision |
| --- | --- |
| Text rendering | Text is laid out, truncated, and drawn by CoreText into an image layer. Cause of the cut-off line: `CATextLayer` ignores `lineHeightMultiple` and cannot truncate wrapped text, so the measured and drawn heights differed. Now a text longer than its line cap is cut at the last allowed line and ends with "…". |
| Title | Shrinks to fit one line, from 6.4% down to 4.2% of the shorter screen edge (Backdrop: 6.8% to 4.6%). A title that still does not fit wraps at the largest size that leaves its last line at least 40% full, else at the smallest size. |
| Poster Focus hierarchy | Three blocks: title with the season tight under it; one facts line (year · genres · airing status · score · watch status, 2 lines max); the overview (4 lines max, 1.32 line height). The uppercase tracked heading is gone. Text column `min(40% width, 74% of the shorter edge)`; poster 70% of the height. |
| Genres | At most 2. Joined with "、" for CJK names and ", " otherwise, as one item in the facts line. |
| Line breaks | Lines break only between items: spaces inside an item are non-breaking and its characters are joined with U+2060 word joiners, because CJK text can otherwise break between any two characters (視 / 聴済み). "TMDb 8.6" stays whole too. Separators are " · " with single spaces. |
| Backdrop facts | Regular weight, 1.9% of the shorter screen edge, at 55% white with a lighter shadow, under the logo or title. (Poster Focus facts: 2%, 58% white.) Samuel asked twice for a quieter line: first 68% white at 2.3%, then smaller and fainter. Rejected: a frosted capsule behind it, which would add a filled shape and draw more attention. |

## Refs

- `ScreenSaverKit/Sources/ScreenSaverKit/ScreenSaverLayouts.swift`
- Validation: `swift test --package-path ScreenSaverKit` (10 passed); `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests'` (succeeded); `make build` (passed). In-process renders reviewed by Claude: Poster Focus with title only, defaults, and all details (Japanese and English, 16:10, ultrawide, portrait), and Backdrop with a logo and with a text title. The render harness was temporary and is not committed.
