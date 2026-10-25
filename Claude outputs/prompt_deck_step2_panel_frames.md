# Deck tab — Step 2/4: painted frame around DeckPanel and CollectionPanel

**Start in Plan Mode. Do not edit any file until I approve the plan.**

## Goal

`assets/menu/deck/frame_ninepatchrect.png` (152×127, 9-slice, transparent centre) frames the two Deck panels, replacing the flat gold-border stylebox. The dark panel fill stays underneath it. We reuse `ScaledNinePatch`, because unlike a theme `StyleBoxTexture` it can shrink the 52×46 px corner ornaments.

## Files in scope

- `scripts/ui/scaled_nine_patch.gd`
- `scenes/menu/deck_overlay.tscn`

## Changes

### `scripts/ui/scaled_nine_patch.gd` — optional fill under the frame
Add two exports (with setters calling `queue_redraw()`, same pattern as the others):
```gdscript
# Vypln POD ramom (napr. tmave pozadie panelu). Alfa 0 = nic sa nekresli.
@export var fill_color: Color = Color(0, 0, 0, 0)
# Odsadenie vyplne od okraja v px ZDROJOVEJ textury (skaluje sa ako patche),
# aby vypln nevytrcala spod vonkajsieho okraja ramu.
@export var fill_inset: float = 0.0
```
In `_draw()`, after the `texture == null` / size guard and before the patch loop: if `fill_color.a > 0.0`, call `draw_rect(Rect2(Vector2.ONE * fill_inset * s, size - Vector2.ONE * 2.0 * fill_inset * s), fill_color)`, where `s = get_effective_scale()` (compute it once and reuse it for the patches). Skip the fill if that rect has no area. Don't change anything else in the file; `draw_center` keeps its meaning.

### `scenes/menu/deck_overlay.tscn`
1. Add ext_resources (`path=` plus the `uid` from the existing `.uid` / `.import` files — don't invent one): `res://scripts/ui/scaled_nine_patch.gd` and `res://assets/menu/deck/frame_ninepatchrect.png`.
2. Replace the `StyleBoxFlat_panel` sub_resource with a `StyleBoxEmpty` (id `StyleBoxEmpty_panel`, all content margins 0), and point both `DeckPanel` and `CollectionPanel` `theme_override_styles/panel` at it. Remove `StyleBoxFlat_panel` completely.
3. Add a `Frame` node as the **first child** of `Layout/Right/DeckPanel` and of `Layout/Right/CollectionPanel` (before `Margin`, so it draws behind the cards). `PanelContainer` stretches it to full rect:
   - `type="Control"`, `script = ScaledNinePatch`, `mouse_filter = 2`, `texture_filter = 2` (Linear, painted UI — architecture.md §6)
   - `texture` = the frame, `patch_margin_left/right = 52`, `patch_margin_top/bottom = 46`
   - `patch_scale = 0.7` (starting value; I'll tune it in the Inspector — `@tool` previews it)
   - `fill_color = Color(0.05, 0.07, 0.12, 0.86)` (the old panel fill), `fill_inset = 3.0`
   - new unique_ids
4. Both `Margin` nodes: margins 14 left/right, 12 top/bottom (the old 8/6 were for a 2 px border; the frame's edge band is ~7 px of the source). These are starting values.

## DO NOT TOUCH

- `scripts/ui/deck_overlay.gd`, `scripts/ui/deck_card_tile.gd`, `scripts/ui/fit_card_grid.gd`
- Every other node and property in `deck_overlay.tscn`: `Layout`, `GodShowcase`, `Right`, the header, `SlotGrid`, the collection header and tabs, `PoolScroll`/`PoolRow`, stretch ratios, unique_ids
- `assets/menu/deck/frame_ninepatchrect.png` and its `.import` (no import changes)
- `MainMenu.tscn`, `main_menu.gd`, other tab pages, `dgb_theme.tres`

## OUT OF SCOPE

- The layout change (avatar on top, Edit bar under the deck, collection only in Edit mode) — Step 3
- The two-row collection — Step 4
- Moving the frame into `dgb_theme.tres` as a theme variation (would need a scalable stylebox; revisit if a third screen uses this frame)
- Mipmaps on the frame texture

## VERIFY

Greps:
- `grep -n "StyleBoxFlat_panel" scenes/menu/deck_overlay.tscn` → nothing
- `grep -n 'name="Frame"' scenes/menu/deck_overlay.tscn` → exactly 2, parents `Layout/Right/DeckPanel` and `Layout/Right/CollectionPanel`
- `grep -rn "frame_ninepatchrect" scenes/ scripts/` → only `deck_overlay.tscn`
- `grep -n "fill_color\|fill_inset" scripts/ui/scaled_nine_patch.gd` → the two exports plus their use in `_draw()`

Editor:
1. Open `deck_overlay.tscn`: both panels show the painted frame with the dark fill inside. No fill pokes out past the frame's outer edge, and corners aren't overlapped or squashed.
2. Changing `patch_scale` on a Frame in the Inspector visibly resizes the corners live.

Runtime (F5 → Deck tab):
3. Both panels are framed, and cards sit inside the frame without touching the border band.
4. The selection glow, tap-then-tap, hold-to-drag, collection swipe and the Edit / Save / Cancel buttons work as before. The frame never swallows taps.
5. No errors in the console.
