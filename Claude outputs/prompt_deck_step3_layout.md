# Deck tab — Step 3/4: stacked layout, Edit bar under the deck, collection only in Edit mode

**Start in Plan Mode. Do not edit any file until I approve the plan.** In the plan, list every node you move or delete in `deck_overlay.tscn` with its old and new `parent=` path.

## Goal

**View mode** (the default when the tab opens) shows, top to bottom: the god avatar, then `DeckPanel` across the full width with all 8 deck cards in **one row**, then a short framed bar holding only an **Edit** button. Tapping deck cards does nothing in this mode.

**Edit mode** (Edit pressed): the avatar hides and `DeckPanel` moves up. The bar swaps Edit for **Cancel** + **Save** and also shows the "CARD COLLECTION" label, the filter tabs **ALL / UNITS / SPELLS** and the hint. The collection cards appear under the bar. This step keeps the collection as **one** horizontal row; Step 4 makes it two rows. Save or Cancel returns to view mode.

The switch is instant; animation is a later step.

## Files in scope

- `scenes/menu/deck_overlay.tscn`
- `scripts/ui/deck_overlay.gd`

## Step A — `deck_overlay.tscn` structure

Target tree:
```
DeckOverlay
└── Layout                 (VBoxContainer — was HBoxContainer; separation 6, mouse_filter 2)
    ├── GodShowcase        (unchanged children GodArt / GodSprite)
    ├── DeckPanel          (Frame + Margin/DeckBox/{Header, SlotGrid})
    └── CollectionPanel    (Frame + Margin/CollectionBox/{CollectionHeader, PoolScroll/PoolRow})
```
1. `Layout`: change `type="HBoxContainer"` to `type="VBoxContainer"`, keeping its anchors, `mouse_filter` and separation.
2. **Delete the `Right` VBox.** Re-parent `DeckPanel` and `CollectionPanel` (and their whole subtrees) from `Layout/Right` to `Layout`, after `GodShowcase`. Fix every descendant's `parent=` path. Keep all unique_ids and every property of the two `Frame` nodes and both `Margin` nodes exactly as they are now (`patch_scale = 0.7`, `fill_*`, margins 14/12).
3. `GodShowcase`: remove `size_flags_stretch_ratio = 0.38`, set `size_flags_horizontal = 3` and `size_flags_vertical = 3`.
4. `DeckPanel`: `size_flags_vertical = 3`, remove `size_flags_stretch_ratio = 1.65` (code sets the ratios, see Step C).
5. `SlotGrid`: add `columns = 8`.
6. Header (`DeckPanel/.../Header`): **move out** `EditButton`, `SaveButton`, `CancelButton`. Logo, Titles and CostBox stay.
7. `CollectionHeader` becomes the bar. `custom_minimum_size = Vector2(0, 34)`. Children in this order:
   `CollectionLabel`, `AllTab`, `UnitsTab`, `SpellsTab` (ALL moves first — reorder the node blocks, keeping each tab's child `Label`), `HintLabel` (keep `size_flags_horizontal = 3`), new `BarSpacer` (`Control`, `size_flags_horizontal = 3`, `mouse_filter = 2`, new unique_id), `CancelButton`, `SaveButton`, `EditButton`.
8. `EditButton` becomes a plain `Button` (it was a gear `TextureButton`): `text = "Edit"`, `custom_minimum_size = Vector2(96, 30)`, `size_flags_vertical = 4`, `unique_name_in_owner = true`, same unique_id. Remove its texture properties and remove the `3_gear` / `4_gear_pressed` ext_resources if nothing else uses them. Give `SaveButton` and `CancelButton` the same `custom_minimum_size = Vector2(96, 30)`; both keep `visible = false`.
9. `CollectionPanel`: keep `size_flags_vertical = 3` in the file (code switches it). `PoolScroll`: add `visible = false`.

## Step B — `deck_overlay.gd` references

- `@onready var edit_button: Button = %EditButton` (type change only).
- New: `@onready var deck_panel: PanelContainer = $Layout/DeckPanel`, `@onready var collection_panel: PanelContainer = $Layout/CollectionPanel`, `@onready var collection_label: Label = $Layout/CollectionPanel/Margin/CollectionBox/CollectionHeader/CollectionLabel`. Alternatively mark these three `unique_name_in_owner` in the scene and use `%` (your choice, say which in the plan).
- Update the file's header comment for the new layout and the "no auto-Edit" rule (remove "Prva interakcia sama zapne Edit mod" and the 5+4 / left-god description). Mixed Slovak/English style.

## Step C — modes

New exports:
```gdscript
# View mod: pomer vysky DeckPanel voci avataru boha (GodShowcase = 1.0).
@export var view_deck_ratio: float = 1.2
# Edit mod: pomer vysky CollectionPanel voci DeckPanel (DeckPanel = 1.0).
@export var edit_collection_ratio: float = 1.3
```
Rewrite `_set_editing(value)`. It keeps everything it does today (button swap, hint text/visibility, clearing the selection when leaving) and adds:
- `god_showcase.visible = not value`
- bar contents: `collection_label`, the three tabs and `hint_label` visible only when `value`; `edit_button` only when `not value`; `save_button` / `cancel_button` only when `value`
- `pool_scroll.visible = value`; on entering Edit, `pool_scroll.scroll_horizontal = 0`
- sizing:
  - view mode: `deck_panel.size_flags_stretch_ratio = view_deck_ratio`, and `collection_panel.size_flags_vertical = Control.SIZE_FILL` (no expand, so the panel collapses to the bar height)
  - Edit mode: `deck_panel.size_flags_stretch_ratio = 1.0`, `collection_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL`, `collection_panel.size_flags_stretch_ratio = edit_collection_ratio`
- set `draggable = value` on every `DeckCardTile` child of `slot_grid` (so hold-to-drag is dead in view mode)

`_make_tile()`: slot tiles (`slot >= 0`) get `tile.draggable = _editing`; pool tiles stay draggable.

## Step D — no auto-Edit

- Delete `_ensure_editing()`.
- `_on_tile_tapped()`, `_on_tile_hold_drag_started()`, `_on_tile_dropped()`: replace the `_ensure_editing()` call with `if not _editing: return`.
- The leave guard (`has_unsaved_changes()` / `confirm_leave()` / `leave_confirmed`), the hero-switch Discard dialog, `_place()`, Save/Cancel/profile logic and the filters stay as they are.

## DO NOT TOUCH

- `scripts/ui/deck_card_tile.gd`, `scripts/ui/fit_card_grid.gd`, `scripts/ui/scaled_nine_patch.gd`
- The `Frame` nodes' properties, the `Margin` margins, the `StyleBoxEmpty_panel` sub_resource
- Header contents other than removing the three buttons (logo, name, synergy, average cost)
- `_place()`, draft/leave-guard logic, `_pool_*_ids()`, `_resize_pool_tiles()`, `_update_header()`, `_update_showcase()` / `_layout_showcase()`
- `main_menu.gd`, `MainMenu.tscn`, other tab pages, `PlayerProfile`, `DeckRules`, `CardDB`

## OUT OF SCOPE

- The two-row collection grid — Step 4
- Slide or fade animation between modes
- Edit-button art (a plain `Button` for now, like Save/Cancel)
- Card Detail on tap in view mode
- The Deck picker (Deck 1/2/…) from the art design

## VERIFY

Greps:
- `grep -n 'name="Right"\|Layout/Right' scenes/menu/deck_overlay.tscn` → nothing
- `grep -n '_ensure_editing' scripts/ui/deck_overlay.gd` → nothing
- `grep -n 'parent="Layout/DeckPanel/Margin/DeckBox/Header"' scenes/menu/deck_overlay.tscn` → no Edit/Save/Cancel among the results
- `grep -n 'EditButton\|SaveButton\|CancelButton\|BarSpacer' scenes/menu/deck_overlay.tscn` → all parented to `.../CollectionHeader`
- `grep -n "columns = 8" scenes/menu/deck_overlay.tscn` → `SlotGrid`
- The scene opens in the editor with no invalid-parent errors

Runtime (F5 → Deck tab):
1. **View mode on open:** the god idle animation centred at the top. Below it the framed deck panel spans the full content width, with the header (logo, name, synergy, average cost) and all 8 cards in one row. Below that a short framed bar with only **Edit** at the right. No collection cards, no filters, no Save/Cancel. The rail, TopBar and footer are still visible.
2. **View mode taps:** tapping a deck card does nothing (no glow, Edit doesn't start). Holding a deck card for 2 s does not start a drag.
3. **Edit:** the avatar disappears and the deck panel moves to the top with 8 cards in one row. The bar shows `CARD COLLECTION | ALL | UNITS | SPELLS | hint … Cancel Save`, with ALL selected. The collection row appears below the bar and scrolls horizontally. Filters work.
4. **In Edit:** tap-then-tap, hold-to-drag from the collection onto a slot, slot-to-slot swaps and the god swap with the Discard dialog all work as before. The synergy line and average cost update live.
5. **Save** → view mode with the new deck. **Cancel** → view mode with the saved deck.
6. **Leave guard:** in Edit with unsaved changes, tap the Shop rail tab → Discard/Cancel dialog. Cancel stays in Edit; Discard switches tabs, and returning to Deck shows view mode.
7. Resize the window (wide and narrow aspect): no overlap, cards shrink to fit, and the bar never gets squeezed below its 34 px.
8. No errors or warnings in the console.
