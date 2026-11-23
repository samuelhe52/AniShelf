# 042.021 — Taglines in caption layouts

## Change

Use 65% text opacity for taglines in every layout, following the Backdrop
visual review. Offer the existing Tagline detail in Deck · Fan, Deck · Pile,
and Timeline. Deck defaults to on; Timeline defaults to off. These layouts
put the tagline below the title block in the existing caption, cap it at two
lines, and update it with the caption. No space is reserved when it is
disabled or absent. Cover Wall, Flip Wall, and Depth Drift remain text-free;
Cover Wall’s small-library fallback still uses Poster Focus.

The snapshot already carries the language-matched text. No schema, artwork, or saved-selection migration is required.

## Validation

- `swift test --package-path ScreenSaverKit`: 21 passed.
- `make test-app-mac APP_TEST_ONLY='MyAnimeListTests/ScreenSaverPublisherTests'`:
  14 passed at the time, including independent saved selections.
- `make build-mac`: passed. An initial compile failed on an untyped `nil`
  branch in the Editorial Cover fit; the optional type is now explicit.
- Reviewed Demo captures with real taglines for [Deck and Timeline](../../.build/tagline-layouts/new-captions.jpg)
  in landscape and portrait, and [the four existing layouts](../../.build/tagline-layouts/existing-layouts.jpg)
  in landscape.
