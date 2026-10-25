# Deck cards — A: big pantheon logo in the bottom-right corner, cropped at the card edge

**Start in Plan Mode. Do not edit any file until I approve the plan.**

## Goal

On every `DeckCardTile` (deck slots and Card Collection), the pantheon logo moves from the top-right to the **bottom-right** and gets **bigger**. Part of it sticks out past the card's right and bottom edges, and that part is **cropped at the card's outer edge**. The `Lv. N` label sits **on top of** the logo, with a thicker outline so it stays readable over it. Everything is code-drawn from the existing `logo_<faction>.png`; there is no new asset. If cropping in code turns out to look bad, I'll paint a dedicated corner asset later.

## File in scope

- `scripts/ui/deck_card_tile.gd` (only this file)

## Changes

1. Constants, near the other layout constants:
   ```gdscript
   # Logo panteonu v pravom dolnom rohu — vacsie, cast vytrca cez okraj karty
   # a je orezana (_logo_clip). Ladit podla artu.
   const LOGO_SIZE := 0.5        # sirka loga ako podiel sirky karty
   const LOGO_OVERHANG := 0.25   # podiel loga, ktory vytrca vpravo aj dole (orezane)
   # Hrubka obrysu "Lv. N" ako podiel velkosti fontu — citatelne aj nad logom.
   const LEVEL_OUTLINE_RATIO := 0.45
   ```
2. New `var _logo_clip: Control`. In `_init()`, create it **right after `_art_clip`** (before `_outline`) with `clip_contents = true` and `mouse_filter = MOUSE_FILTER_IGNORE`, and move the existing `_logo` creation so `_logo` becomes a child of `_logo_clip` instead of the tile. Draw order is then art → logo → outline → status → **level** → cost badge, which puts the level label above the logo. Keep `_logo`'s `expand_mode`, `stretch_mode` and `mouse_filter`.
3. `_layout()` — replace the current `_logo` line (the top-right placement):
   - `_set_rect(_logo_clip, card)` (the card rect only, so the progress bar below it is never covered)
   - `logo_w = card.size.x * LOGO_SIZE`; `logo_h` from the texture's aspect (`logo_w * tex.y / tex.x` when a texture is set, else `logo_w`)
   - local position inside the clip: `Vector2(card.size.x - logo_w * (1.0 - LOGO_OVERHANG), card.size.y - logo_h * (1.0 - LOGO_OVERHANG))`, size `Vector2(logo_w, logo_h)`
4. `setup()`: `_logo_clip.visible = _logo.texture != null` (keep `_logo.visible` as it is).
5. Level label outline: in `_layout()`, after the level font size is set, call `_level_label.add_theme_constant_override("outline_size", maxi(4, int(font * LEVEL_OUTLINE_RATIO)))`. The level label's position and right alignment stay as they are.
6. Update the header comment: the logo is now bottom-right, partly cropped, under the level label.

## DO NOT TOUCH

- Cost badge, status label, progress bar, glow / outline, art layout, input / drag code, `logo_for()`, `width_for_height()`
- `deck_overlay.gd`, `deck_overlay.tscn`, `deck_tile.gd` (Pantheon tiles), `card_detail.*`
- The `DeckOverlay` header's `PantheonLogo` next to the god's name (it stays as it is)

## OUT OF SCOPE

- A dedicated painted corner-logo asset
- Moving the level label or changing its font
- Logos on the Pantheon-tab tiles (`DeckTile`)
- Double-tap → Card Detail (prompt B)

## VERIFY

- `grep -n "_logo_clip" scripts/ui/deck_card_tile.gd` → declared, created in `_init()`, laid out in `_layout()`, visibility set in `setup()`
- `grep -n "card.position.y + w \* 0.03" scripts/ui/deck_card_tile.gd` → nothing (old top-right placement gone)

Runtime (F5 → Deck tab, View and Edit):
1. On every card, a large pantheon logo fills the bottom-right corner. It's visibly cut off along the card's right and bottom edges, never drawn outside the card, and never over the collection progress bar.
2. `Lv. N` is drawn over the logo with a clearly thicker black outline and is readable on both big deck cards and small collection cards.
3. The top-right corner is free (no logo there any more); the cost badge is unchanged at top-left.
4. Locked or forbidden cards dim the logo together with the rest of the card.
5. A pantheon without a logo file shows no logo and no error.
6. Resize the window: the logo scales with the card and the crop stays at the card edge.
