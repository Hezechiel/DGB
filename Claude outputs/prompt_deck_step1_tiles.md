# Deck tab — Step 1/4: cards show their own painted frame, no locked slot

**Start in Plan Mode. Do not edit any file until I approve the plan.** In the plan, report the real pixel size of a unit card `scroll_texture`, a spell card `scroll_texture` and `hero_zeus.tres`'s `card_art` (read the `.tres` / AtlasTexture regions / PNG sizes), and the resulting width/height aspect for each.

## Goal

Card art now has its own painted frame. `DeckCardTile` must stop drawing `frame_ninepatchrect.png` over every card and stop cropping the art, so the whole painted card (frame included) is visible. The deck also loses the fake locked 9th slot, because there is no slot-unlock mechanic. The frame texture is **not** deleted: Step 2 reuses it around the two panels.

## Files in scope

- `scripts/ui/deck_card_tile.gd`
- `scripts/ui/deck_overlay.gd`

## Changes

### `scripts/ui/deck_card_tile.gd`
1. Remove `FRAME_TEXTURE`, `FRAME_MARGIN_H`, `FRAME_MARGIN_V`, `FRAME_BORDER_PX` and `ART_CROP`, the `_frame: ScaledNinePatch` var, and its creation block in `_init()`.
2. `_art.stretch_mode` → `TextureRect.STRETCH_KEEP_ASPECT_CENTERED` (was `KEEP_ASPECT_COVERED`), so the painted frame is never clipped. Keep `_art_clip` (it still bounds the art).
3. `_layout()`:
   - guard on `_art_clip == null` instead of `_frame == null`
   - `art_rect = card` (no inset); `_art` fills `art_rect` with no crop (`Rect2(Vector2.ZERO, art_rect.size)`)
   - level label: replace `inset * 0.3` with `w * 0.03` as bottom padding
   - glow / outline / cost badge / logo / status / progress bar positions stay exactly as computed today
4. `_begin_drag()`: `pic.size = _art_clip.size * 0.9` (was `_frame.size * 0.9`).
5. Update the header comment: the art carries its own painted frame, and the tile only overlays the cost badge, pantheon logo, level, status and progress bar. Mixed Slovak/English style.

### `scripts/ui/deck_overlay.gd`
1. Delete the `LockedSlot` inner class and the `slot_grid.add_child(LockedSlot.new())` line (with its comment) in `_rebuild_slots()`. The grid then holds 8 tiles (god + 7) and `FitCardGrid` centres the shorter second row (5 + 3). The one-row layout comes in Step 3.
2. Update the header comment: remove "+ zamknuty slot v mriezke 5+4".

### `CARD_ASPECT`
Keep `0.82` unless the sizes you report in the plan differ by more than ±0.02. If they do, propose the new value in the plan and wait for my answer. Cards and gods must share one aspect, or flag it if they can't.

## DO NOT TOUCH

- `scripts/ui/scaled_nine_patch.gd` and `assets/menu/deck/frame_ninepatchrect.png` (needed in Step 2)
- `scripts/ui/fit_card_grid.gd`, `scenes/menu/deck_overlay.tscn`
- `scripts/ui/deck_tile.gd` (Pantheon tab tiles), `pantheon_overlay.*`, `card_detail.*`
- Deck logic in `deck_overlay.gd`: `_place()`, draft / Save / Cancel / leave guard, filters, hold-to-drag, `_ensure_editing()` (changed in Step 3)
- `PlayerProfile`, `CardDB`, `DeckRules`, any `.tres` data

## OUT OF SCOPE

- Panel frames, the layout change (avatar on top, Edit bar, 2-row collection) — Steps 2–4
- Moving or restyling the cost badge, logo or level label to fit the painted frames (tune later, once real art is in place for every card)
- Any new slot or deck-size mechanic

## VERIFY

Greps (all must return nothing):
- `grep -n "FRAME_TEXTURE\|FRAME_MARGIN\|FRAME_BORDER_PX\|ART_CROP\|_frame" scripts/ui/deck_card_tile.gd`
- `grep -n "LockedSlot" scripts/ui/deck_overlay.gd`
- `grep -rn "frame_ninepatchrect" scripts/` (the asset stays on disk, unreferenced until Step 2)

Runtime (F5 → Deck tab):
1. The deck shows exactly 8 tiles (god + 7 cards) in a 5 + 3 grid, with no lock tile.
2. Every card shows its full painted frame: no extra dark frame around it, and no edge of the art cut off on any side, in both the deck and the collection.
3. Cost badge, logo, "Lv. N", "IN DECK" / "LOCKED" / "FORBIDDEN" and the collection progress bar still appear in the same places.
4. Tap-then-tap and hold-to-drag still work. The drag preview shows the card art at about 90 % of the tile size.
5. The selection glow and outline still pulse around the selected card.
6. The Pantheon tab tiles look unchanged.
7. No errors in the console.
