# AniShelf Chinese promo video

A 30-second, 1920×1080 Remotion promo built from AniShelf product screenshots.

## Preview

```bash
npm install
npm run dev
```

Open the `AniShelf-Promo-ZH` composition. Each scene is also registered separately under `AniShelf-Promo-Scenes` for quicker iteration.

## Structure

- Intro: AniShelf identity and a three-screen reveal.
- iCloud sync: cross-device sync, backup, restore, and export.
- Next episode notifications: enabled state, next episode, and notification management.
- Ratings and episode progress: ratings and episode-level tracking across the library and detail views.
- More updates: text-only update wall.
- End card: app icon and Chinese tagline.

Source screenshots are copied into `public/screenshots` so the composition remains self-contained.

## Audio and output

Rendered videos and local music files are intentionally excluded from Git. The final soundtrack is a locally supplied, normalized 30-second edit of "Sonare" by TOMOO with a fade-out, muxed into the rendered video after export.
