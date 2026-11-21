# 044 — Layout design notes

Living document. Design rules for the layouts that started as Demo drafts and ship since
[044](../042-mac-screen-saver/000-plan.md). They moved here from the [042 idea backlog](../042-mac-screen-saver/backlog.md)
when the layouts shipped; update them in place when a layout's design changes.

| Layout | Source | Design rules |
| --- | --- | --- |
| **Deck**: cards as a stack, one poster at a time, title underneath. Two sub-styles: **Fan** (the front card is dealt off, the rest fan behind it) and **Pile** (a tall pile seen head-on, each card peeking above the one in front, the whole pile leaning slightly and a little more with depth; the top card is tossed toward the viewer and the pile moves up; a soft colour wash from the top posters behind; title and library count in a corner) | PR #28; Pile from Samuel's reference image, 2026-11-21 | Drive the cards and the caption from one model; let the leaving card animate on its own so no step waits on another; tie every delayed step to the session token. Pile must stay orderly: one shared lean, not random twists per card. |
| **Flip Wall**: a still grid where single tiles flip over to show another poster, like Apple's Album Artwork saver (rows and flip delay as options) | Samuel, 2026-11-20 | A separate layout, not a Cover Wall option. Reuse the Cover Wall rows setting. Flips should be rare and calm: a sketch that flipped every second or two felt frantic, so default to several seconds and keep it configurable. One timer tied to the session token; never flip the same tile twice in a row or show a poster already on screen. |
| **Cover Fusion**: full-height poster on one side, inner edge feathered into a heavy blur of itself, text in the rest | PR #28 (edge rebuilt in `d6293e96`: sharp to ~72% width, then a medium blur, gradient baked into pixels) | Size the poster from the shorter screen edge; stack on portrait. Make the blurred wash smooth, not a bright blob at the poster edge. The baked-gradient technique is worth reusing. |
| **Timeline**: a slow pan along a line of posters, alternating above and below, with the poster at the centre emphasised and named. The line can mean when it **aired**, when the user **started watching**, or when they **finished** | Brainstorm, 2026-11-21 | See [015](../042-mac-screen-saver/015-timeline-chronology-and-pacing.md) for chronology, markers, and pacing, and [016](../042-mac-screen-saver/016-timeline-date-options.md) for the date options. |
| **Depth Drift**: posters float slowly upward at different depths, soft and large up close, small and slow far away, a few sharp at the focus plane; no text | Brainstorm, 2026-11-21 | Blur is baked per spawn. See [017](../042-mac-screen-saver/017-depth-drift-density.md) for the layer budget, staggered opening, and protected focus band. |
| **Editorial Cover**: a magazine cover with one large headline tinted by the poster, a tilted poster, and a separate metadata column | Brainstorm, 2026-11-21 | Give the full title first claim on space. Fit the poster below or beside the rendered lines so the tilt reaches into empty space without covering the headline. Hero Still's logo art is an alternative to the headline, not a second title. |

When the overview is enabled and present, Editorial Cover reserves space for a short excerpt
before fitting the headline. The overview uses up to six lines and shares the remaining
height with the poster in portrait. Text that exceeds either limit ends with an ellipsis.

In Deck · Fan, the outgoing poster sweeps upward and outward along one continuous
curve and tilts with the same easing. It stays opaque while crossing the next poster. The
caption changes as the outgoing card clears the new front, and the new rear card slides out
from behind the hand. Exit travel is sized in card widths so the reveal does not depend on
the display aspect ratio.

In Deck · Pile, the front card grows and turns as it is tossed up and left, then
fades once the next poster is readable. The rest of the pile advances together, with the
incoming card joining from one slot deeper. The caption follows the reveal.

Timeline centers the visible glyphs vertically inside each year badge, including the wrap
arrow. Centering the font's line box leaves too much space below the digits.

In Depth Drift, the nearest plane uses a blur radius of 3% of poster width.
At 6%, the foreground lost its artwork and spread a veil over the sharp posters behind it.

## Duration controls

AniShelf settings and the Demo use the same stepped sliders for Interval, Flip Delay,
and Timeline Hold Duration. Use one tick per preset, not one per second: the stops
are spaced evenly on screen even when the gaps between durations are not. AniShelf
loads only saved presets; other values use the control's default. Flip Delay starts
at 3 seconds, its default. Timeline Hold Duration offers 4, 6, 8, 10, 20, 30, 60,
and 120 seconds, defaulting to 8.
