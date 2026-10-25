# Deck tab — Step 4/4: two-row Card Collection (horizontal scroll)

**Start in Plan Mode. Do not edit any file until I approve the plan.**

## Goal

In Edit mode the Card Collection shows **two rows** of cards and scrolls **horizontally**. Cards fill **column by column** (top, then bottom, then the next column), so the sort order (owned first → cost → id; gods first under ALL) reads left to right in pairs. Tiles size themselves from the scroll area's height so exactly two rows fit. Swipe-to-scroll, tap-then-tap, hold-to-drag, filters and the in-deck / forbidden states behave as now.

## Files in scope

- `scenes/menu/deck_overlay.tscn`
- `scripts/ui/deck_overlay.gd`

## Changes

### `scenes/menu/deck_overlay.tscn`
Replace `PoolRow` (`HBoxContainer`) under `.../CollectionBox/PoolScroll` with **`PoolGrid`** (`GridContainer`):
- same unique_id as the old `PoolRow`, `unique_name_in_owner = true`, `layout_mode = 2`, `size_flags_vertical = 0`, `mouse_filter = 2`
- `columns = 1` (code sets the real value), `theme_override_constants/h_separation = 8`, `theme_override_constants/v_separation = 6`
- `PoolScroll` stays as is (`vertical_scroll_mode = 0`, `visible = false`)

### `scripts/ui/deck_overlay.gd`
1. `@onready var pool_grid: GridContainer = %PoolGrid` replaces `pool_row`. Rename every use. `grep pool_row` must come back empty.
2. Constants:
   ```gdscript
   # Kolekcia ma pevne 2 riadky, scroll je horizontalny.
   const POOL_ROWS := 2
   const POOL_V_SEPARATION := 6.0   # musi sediet s v_separation PoolGrid v scene
   ```
3. `_rebuild_pool()` — keep the selection clear, the `_free_children()` call and the same id lists in the same order (gods first under ALL, then `_pool_card_ids()`). Then lay the entries out **column-major** in a row-major `GridContainer`:
   - `n` = number of entries, `cols = maxi(1, ceili(float(n) / POOL_ROWS))`, `pool_grid.columns = cols`
   - entry `i` goes to grid cell `(i % POOL_ROWS) * cols + (i / POOL_ROWS)`. Build an array of `POOL_ROWS * cols` cells, put each tile in its cell, then `add_child` in cell order.
   - an empty cell (odd `n`, the bottom of the last column) gets a plain filler `Control` (`mouse_filter = MOUSE_FILTER_IGNORE`), so the top row stays aligned
   - then `_resize_pool_tiles()` and `_refresh_pool_states()` as today
   
   Comment it briefly in Slovak/English: why column-major, and why there's a filler.
4. `_resize_pool_tiles()` — row height from the scroll area:
   ```gdscript
   var avail := pool_scroll.size.y - POOL_SCROLLBAR_SPACE - POOL_V_SEPARATION * (POOL_ROWS - 1)
   var h := maxf(40.0, avail / POOL_ROWS)
   var w := DeckCardTile.width_for_height(h, CARD_ASPECT, true)
   ```
   Apply `custom_minimum_size = Vector2(w, h)` to **every** child of `pool_grid`, fillers included.
5. `_refresh_pool_states()` iterates `pool_grid` children. The existing `as DeckCardTile` + `null` skip already ignores fillers; keep it.
6. Update the header comment line about the collection ("dole Card Collection … horizontalny scroll") to say two rows, column-major.

## DO NOT TOUCH

- `scripts/ui/deck_card_tile.gd`, `fit_card_grid.gd`, `scaled_nine_patch.gd`
- `_set_editing()` and the mode/ratio logic (`view_deck_ratio`, `edit_collection_ratio`), the bar, the header, `SlotGrid`, the `Frame` / `Margin` nodes
- `_place()`, the draft / Save / Cancel / leave guard, `_pool_hero_ids()` / `_pool_card_ids()` sort logic, filters
- `main_menu.gd`, `MainMenu.tscn`, other tab pages, `PlayerProfile`, `CardDB`, `DeckRules`

## OUT OF SCOPE

- Vertical scrolling or a configurable row count
- A slide animation between modes
- Scroll snapping, page indicators, momentum tuning
- Lazy or virtualized tiles (the collection is small)

## VERIFY

Greps:
- `grep -n "pool_row\|PoolRow" scripts/ui/deck_overlay.gd scenes/menu/deck_overlay.tscn` → nothing
- `grep -n 'name="PoolGrid"' scenes/menu/deck_overlay.tscn` → one `GridContainer` under `.../PoolScroll`
- `grep -n "POOL_ROWS" scripts/ui/deck_overlay.gd` → the constant plus its use in `_rebuild_pool()` and `_resize_pool_tiles()`

Runtime (F5 → Deck tab → Edit):
1. The collection shows exactly two full rows. Both rows are fully visible above the horizontal scrollbar, with nothing clipped at top or bottom.
2. Order: the first column is items 1–2, the next column 3–4, and so on (with ALL: gods first, then owned cards by cost, then locked).
3. An odd number of items (try a filter that gives an odd count): the last column has only a top card and nothing shifts.
4. UNITS / SPELLS / ALL rebuild the grid and reset the scroll to the start.
5. Swipe scrolls horizontally. A short tap selects, and hold-to-drag onto a deck slot works from both rows. IN DECK / FORBIDDEN / LOCKED labels and the progress bars show as before.
6. Resize the window: tiles resize so two rows always fit.
7. Save / Cancel → view mode, then Edit again → the grid is rebuilt correctly.
8. No errors in the console.

Tuning note for me (not for Claude Code): if the tiles feel small, raise `edit_collection_ratio` in the Inspector (currently 1.3).
