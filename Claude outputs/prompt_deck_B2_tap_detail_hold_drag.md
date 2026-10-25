# Deck tab — B: tap = Card Detail, hold 1 s = drag (no tap-to-select any more)

**Start in Plan Mode. Do not edit any file until I approve the plan.**

## Goal — new gesture set for `DeckCardTile`

| Gesture | View mode | Edit mode |
|---|---|---|
| **Tap** (any card: deck slot or collection; owned, locked or forbidden) | Card Detail | Card Detail |
| **Swipe** | — | scrolls the collection (as now) |
| **Hold `hold_to_drag_time` (1.0 s)** on an owned, allowed card | — | the glow "charges" during the hold. When it's full, the card **lifts**: its spot becomes **empty**, and a full-size copy of the card **follows the finger** |
| **Release over a valid deck slot** | — | placed (existing `_place()` rules: a card replaces or swaps, a god on slot 0 switches decks; a unit on the god slot isn't accepted) |
| **Release anywhere else** | — | drag cancelled, nothing changes, the card reappears in its spot |

**Tap-then-tap selection is removed completely** (no selection glow, no "tap a slot to place"). The glow exists only as hold feedback.

**The collection no longer lists what's in the draft.** Cards in the current draft, and under ALL the current draft god, are left out of the collection. When a card lands in the deck, the collection is rebuilt and re-sorted, so the card it replaced shows up there again in its sorted position. (The "IN DECK" label in the collection goes away with this.)

Card Detail is the same fullscreen overlay the Pantheon tab uses (`main_menu.gd` already owns it).

## Files in scope

- `scripts/ui/deck_card_tile.gd`
- `scripts/ui/deck_overlay.gd`
- `scripts/ui/main_menu.gd`

## Changes

### `scripts/ui/deck_card_tile.gd`
1. **Tap:** in `_gui_input()`'s release branch, emit `tapped` for every tap (distance ≤ `TAP_MAX_DISTANCE`), **without** the `not is_blocked()` condition, so locked and forbidden cards open their detail too. A press that moved more than `TAP_MAX_DISTANCE` (a scroll) or turned into a drag never counts as a tap (keep that).
2. **Remove selection:** delete `_selected`, `set_selected()`, `_glow_tween` and the pulsing-tween code. `_refresh_glow()` then shows the glow/outline only while holding (`_pressed and _hold_elapsed >= HOLD_FEEDBACK_DELAY and _can_drag()`), with alpha driven by `_process()` as today. The glow is hidden as soon as the drag starts or the press ends.
3. **Empty spot while dragging:** in `_apply_state()`, while `_dragging`, set `modulate.a = 0.0` (was 0.45). The tile keeps its layout cell, so the spot stays visibly empty. `NOTIFICATION_DRAG_END` restores it (existing code), which covers a cancelled drop.
4. **Drag preview = the card on the finger:** in `_begin_drag()`, build the preview at **full tile card size** (`_art_clip.size`, not 0.9×), centred on the finger, `modulate.a = 1.0`. Draw the art plus the cost badge if it's simple to replicate; if not, art only is fine. Say which in the plan. Keep `force_drag()` and the payload `{"id", "kind", "from_slot"}` unchanged.
5. `_can_drop_data()` / `_drop_data()`: unchanged (a unit on slot 0 is already rejected; same id is rejected).
6. Update the header comment for the gesture table above (Slovak/English mix).

### `scripts/ui/deck_overlay.gd`
1. `signal card_detail_requested(id: StringName, kind: StringName)` (same as `PantheonOverlay`'s).
2. `hold_to_drag_time` default `2.0` → `1.0`.
3. `HINT_TEXT` → `"Tap: details · hold %.0fs and drag onto the deck"`.
4. `_on_tile_tapped(tile)` → just `card_detail_requested.emit(tile.item_id, tile.kind)`, no `_editing` gate (both modes).
5. **Remove all selection state:** `_selected`, `_clear_selection()` and every call to it, the tap-then-tap branch, and `_on_tile_hold_drag_started()` (plus its `connect` in `_make_tile()`; leave the signal itself in the tile).
6. **Collection excludes the draft:**
   - `_pool_card_ids()`: skip ids in `_draft_cards`
   - `_pool_hero_ids()` (ALL filter): skip `_draft_hero`
   - `_refresh_pool_states()`: in-deck is always `false` (`tile.set_state(false, forbidden)` for cards, `set_state(false, false)` for gods). Keep the forbidden logic.
7. **Rebuild the collection when the draft changes:** `_refresh_draft_view()` calls `_rebuild_pool()` instead of `_refresh_pool_states()`. **Preserve the horizontal scroll** across that rebuild: read `pool_scroll.scroll_horizontal` before, then set it back with `call_deferred` after the grid has re-laid out. The explicit resets to 0 (filter change, entering Edit) stay.
8. `activate()` / `_on_profile_changed()`: make sure the pool is built **after** the draft is loaded, so the exclusion uses the right draft (reorder calls if needed and say so in the plan).
9. Update the header comment: tap = detail in both modes, Edit = hold-drag only, collection = cards not in the deck.

### `scripts/ui/main_menu.gd`
- In `_ready()`, next to the Pantheon line: `deck_overlay.card_detail_requested.connect(_on_card_detail_requested)`. The existing handler already hides the menu chrome and opens `CardDetail`; closing returns to the Deck tab in the same mode and with the draft intact.

## DO NOT TOUCH

- `_place()` rules, the hero switch + Discard dialog, Save / Cancel, the leave guard, the mode switch and ratios, filters, the two-row column-major `PoolGrid` layout and filler logic
- `deck_card_tile.gd` layout from the previous step (cropped corner logo, level outline), the cost badge, status / progress bar code
- `deck_tile.gd` and `pantheon_overlay.gd` (Pantheon already opens the detail on a single tap)
- `card_detail.gd` / `card_detail.tscn`, `PlayerProfile`, `CardDB`, `DeckRules`

## OUT OF SCOPE

- A "Use" button in Card Detail
- Dropping a card back onto the collection as an "explicit remove" (the deck always has 7; release over the collection = cancel)
- Animations (fly-back on cancel, landing pop), haptics
- Auto-scrolling the collection while dragging near its edge
- Double-tap gestures anywhere

## VERIFY

Greps:
- `grep -n "_selected\|set_selected\|_clear_selection\|_glow_tween" scripts/ui/deck_card_tile.gd scripts/ui/deck_overlay.gd` → nothing
- `grep -n "deck_overlay.card_detail_requested" scripts/ui/main_menu.gd` → one connect
- `grep -n "hold_to_drag_time: float = 1.0" scripts/ui/deck_overlay.gd` → one

Runtime (F5 → Deck tab):
1. **View:** tapping a deck card or the god → Card Detail fullscreen; close → still View. Holding a card does nothing.
2. **Edit, tap:** tap a collection card (owned, locked, forbidden) or a deck slot → Card Detail; close → still Edit, draft unchanged. Nothing gets a selection glow from a tap.
3. **Edit, hold:** hold an owned card. After ~0.15 s the glow appears and fills up over 1 s. Then the card's spot goes empty and the full-size card follows the finger. Releasing earlier than 1 s = a normal tap (Card Detail), with no drag.
4. **Valid drop:** drop on a deck slot → it shows the new card. The collection re-sorts: the dropped card is gone from it, the replaced card appears in its sorted place, and the scroll doesn't jump back to the start. Average cost and the synergy line update.
5. **Invalid drops:** a unit on the god slot, empty panel space, the bar, the collection, outside the Deck page → nothing changes and the card reappears in its spot.
6. **Deck slot → deck slot** drag swaps the two (as before). Dragging a deck card onto the collection cancels.
7. **God:** under ALL, the current god is not in the collection. Dragging another owned god onto slot 0 switches decks (with the Discard dialog when there are card changes), and the collection rebuilds for the new god's deck.
8. Locked or forbidden cards don't glow or lift on hold, but open the detail on tap.
9. Level up in Card Detail opened from Edit → close → the tile updates, the draft is unchanged.
10. Save / Cancel / leave guard behave as before. No errors in the console.
