# Claude Code prompt — Scrolls step 5a: Deck screen with edit mode

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 4 is merged (`scripts/ui/shop_overlay.gd` and `CardDB.list_pack_ids()` exist). If not, stop and tell me.

Line numbers below refer to the files as they are after step 4.

## Goal

The main menu's **Heroes** button opens a Deck screen (SWFA-style): one row of **8 slots — the god on the far left, then the 7 cards**. An **Edit** button reveals the pool of gods and cards below; the player places them into slots by **drag and drop** or by **tap, then tap**, and saves.

No upgrades, no card detail view, no encyclopedia in this step. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. `scripts/CardDB.gd` — two sorted id lists

Add directly after `list_pack_ids()` (line 61), same shape:

```gdscript
# Zoradene id-cka — deterministicke poradie pre UI zoznamy.
func list_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_cards.keys())
	ids.sort()
	return ids

func list_hero_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_heroes.keys())
	ids.sort()
	return ids
```

## 2. New file `scripts/ui/deck_tile.gd`

One tile = one god or one card, used both for the 8 deck slots and for the pool. Built entirely in code (no `.tscn`), plain default-theme controls.

```gdscript
extends PanelContainer
class_name DeckTile

# DeckTile — jedna dlazdica (boh alebo karta) v Deck obrazovke. Pouziva sa
# pre 8 slotov balicka aj pre pool. Sama NIC nemeni — len hlasi tap a
# drag&drop cez signaly/callbacky; logiku drzi DeckOverlay.

signal tapped(tile: DeckTile)
# Emitovany na CIELOVEJ dlazdici, ked na nu nieco pustia.
signal dropped(source: Dictionary, target: DeckTile)

const KIND_HERO := &"hero"
const KIND_CARD := &"card"
const TILE_SIZE := Vector2(124, 150)

var item_id: StringName = &""
var kind: StringName = KIND_CARD
var slot_index: int = -1      # 0 = boh, 1..7 = karty, -1 = dlazdica v poole
var locked: bool = false      # nevlastnene — sede, neda sa vybrat ani tahat
var interactive: bool = false # false mimo edit modu
```

Required behaviour:

- `_init()` / `_ready()`: `custom_minimum_size = TILE_SIZE`; children built in code — a `VBoxContainer` with a `TextureRect` (`expand_mode = EXPAND_IGNORE_SIZE`, `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`, `size_flags_vertical = SIZE_EXPAND_FILL`), a name `Label`, and an info `Label`. Children get `mouse_filter = MOUSE_FILTER_IGNORE` so the tile itself receives input.
- `setup(id: StringName, tile_kind: StringName, slot: int) -> void`: stores the fields and fills the visuals:
  - card: texture = `CardData.scroll_texture`, name = `display_name`, info = `"Cost %d · Lv %d"` (level from `PlayerProfile.get_card_level(id)`; for a locked card `"Cost %d · Locked"`).
  - god: texture = first frame of the god's idle animation if available — check `sprite_frames != null` and `has_animation()` for `&"iddle_left"` (the spelling both current gods use) then `&"idle_left"`, use `get_frame_texture(anim, 0)`; otherwise no texture. Name = `display_name`, info = `"God · Lv %d"` or `"God · Locked"`.
  - `locked = not owned` (via `PlayerProfile.owns_card` / `owns_hero`); locked tiles get `modulate = Color(0.45, 0.45, 0.45)`.
- `set_selected(value: bool)` — visible highlight (`self_modulate` tint is enough).
- `set_in_deck(value: bool)` — for pool tiles: append `" · In deck"` to the info text (rebuild the text, do not keep appending).
- Tap: in `_gui_input`, handle `InputEventMouseButton` with the left button only. On press, remember `event.position`. On release, when `interactive and not locked` and the release is within 10 px of the remembered press position → `tapped.emit(self)`. The distance check stops a finger that was scrolling the pool from selecting the tile it lifts off. (The project has `emulate_touch_from_mouse` on and Godot's default mouse-from-touch emulation, so mouse-button events cover both desktop and touch. Do not also handle `InputEventScreenTouch`, or every tap fires twice.)
- Drag and drop with Godot's built-in Control API:
  - `_get_drag_data(_pos)`: return `null` unless `interactive and not locked and item_id != &""`; otherwise `set_drag_preview(...)` (a small `Label` with the name is enough) and return `{"id": item_id, "kind": kind, "from_slot": slot_index}`.
  - `_can_drop_data(_pos, data)`: `true` only if `interactive`, this tile is a **slot** (`slot_index >= 0`), `data` is a Dictionary with a `"kind"`, and the kind fits the slot (`KIND_HERO` only on slot 0, `KIND_CARD` only on slots 1–7).
  - `_drop_data(_pos, data)`: `dropped.emit(data, self)`.

## 3. New `scripts/ui/deck_overlay.gd` + `scenes/menu/deck_overlay.tscn`

Same overlay pattern as `scripts/ui/shop_overlay.gd` / `scenes/menu/shop_overlay.tscn` (fullscreen `Control`, hidden by default, `open()` / `close()`, `signal closed`, code-based connections only).

Scene tree (plain controls, no art):

```
DeckOverlay (Control, full rect, script deck_overlay.gd)
└── DeckPanel (Panel, full rect)
    └── Margin (MarginContainer, full rect, 16 px margins)
        └── Content (VBoxContainer)
            ├── Header (HBoxContainer)
            │   ├── TitleLabel (Label, text "Deck", expand)
            │   ├── EditButton (Button, "Edit")
            │   ├── SaveButton (Button, "Save", hidden)
            │   ├── CancelButton (Button, "Cancel", hidden)
            │   └── CloseButton (Button, "Close")
            ├── SlotRow (HBoxContainer)            — 8 DeckTiles, built in code
            ├── HintLabel (Label, hidden)
            └── PoolScroll (ScrollContainer, expand vertical, hidden,
                │           horizontal scroll disabled)
                └── PoolGrid (GridContainer, columns = 8) — built in code
```

`deck_overlay.gd` (`class_name DeckOverlay`):

State:

```gdscript
var _editing: bool = false
var _draft_hero: StringName = &""
var _draft_cards: Array[StringName] = []   # vzdy presne PlayerProfile.DECK_SIZE
var _selected: DeckTile = null             # tap-then-tap vyber
```

- `open()`: load the draft from `PlayerProfile.get_deck_hero()` / `get_deck_cards()`, leave edit mode, rebuild, `visible = true`.
- `close()`: if editing, discard the draft first (same as Cancel); `visible = false`; `closed.emit()`.
- **View mode** (default): `SlotRow` shows the saved deck; tiles are not interactive; pool and hint hidden; only `EditButton` and `CloseButton` visible.
- **Edit mode** (`EditButton`): tiles interactive; `PoolScroll` and `HintLabel` (`"Drag a scroll onto a slot, or tap a scroll and then a slot."`) shown; `SaveButton` and `CancelButton` shown, `EditButton` hidden.
- **Pool content**, rebuilt on entering edit mode and after every change: first every god from `CardDB.list_hero_ids()`, then every card from `CardDB.list_card_ids()` whose `obtain_source != 0` (test cards never appear). Within each group: owned first, then locked; cards ordered by `cost`, then id. Pool tiles have `slot_index = -1`; a tile whose id is in the draft is marked `set_in_deck(true)`.
- **One placement function** used by both drag-drop and tap-then-tap:

```gdscript
# Jedine miesto, kde sa meni draft. kind musi sediet so slotom (0 = boh).
# Karta, ktora UZ je v drafte na inom slote, sa s cielovym slotom VYMENI —
# draft tak nikdy neobsahuje duplikat ani prazdny slot.
func _place(id: StringName, kind: StringName, to_slot: int) -> void
```

  - `to_slot == 0`: only `KIND_HERO`, and only an owned god → `_draft_hero = id`.
  - `to_slot` 1–7: only `KIND_CARD`, only an owned card. Let `target = to_slot - 1`. If `id` is already at index `j` in `_draft_cards` → swap entries `j` and `target`. Otherwise `_draft_cards[target] = id`.
  - Anything else is ignored. After a change: clear the selection and rebuild slots and pool.
- **Tap, then tap:** tapping an unlocked pool tile or a slot tile selects it (highlight; tapping it again deselects). With something selected, tapping a **slot** calls `_place(selected.item_id, selected.kind, slot.slot_index)`. Tapping another pool tile just moves the selection.
- **Drag and drop:** on a slot tile's `dropped` signal → `_place(source["id"], source["kind"], target.slot_index)`.
- **Save:** `PlayerProfile.set_deck(_draft_hero, _draft_cards)`. On `true` → back to view mode. On `false` → `push_warning`, stay in edit mode (should not happen, since the draft is always complete and owned).
- **Cancel:** reload the draft from the profile, back to view mode.
- Free old tiles with `queue_free()` when rebuilding.

## 4. `scripts/ui/main_menu.gd` + `scenes/menu/MainMenu.tscn`

Mirror exactly how step 4 wired `ShopOverlay`:

- `MainMenu.tscn`: one `ext_resource` for `res://scenes/menu/deck_overlay.tscn` (by `path=` only) and one instanced node `DeckOverlay` as a child of the root, after `ShopOverlay`, `visible = false`.
- `main_menu.gd`: `@onready var deck_overlay: DeckOverlay = $DeckOverlay`; replace `heroes_button.pressed.connect(_show_coming_soon.bind("Heroes"))` with `heroes_button.pressed.connect(_on_heroes_button_pressed)`; add `deck_overlay.closed.connect(_on_deck_overlay_closed)`; two handlers identical in shape to the shop ones (hide `nav_rail` and `main_content`, `move_to_front()`, `open()`; restore both on close).
- The button and variable keep the name `heroes_button` (it will be renamed later). The **Deck** (inventory icon) and **Rewards** buttons keep their "coming soon" toast.

## DO NOT TOUCH

- `scripts/PlayerProfile.gd` (use only `get_deck_hero`, `get_deck_cards`, `set_deck`, `owns_card`, `owns_hero`, `get_card_level`, `get_hero_level`, `DECK_SIZE`).
- `scripts/pack_roller.gd`, `scripts/pack_data.gd`, `scripts/ui/shop_overlay.gd`, `scenes/menu/shop_overlay.tscn`.
- `scripts/BattleManager.gd`, `scripts/MatchConfig.gd`, `scripts/ui/prematch_flow.gd`, `scripts/level_curve.gd`.
- Everything under `scripts/arena/` and `scenes/arena/` (the in-match `Card` scene is not reused here).
- Everything under `data/` and `assets/`.
- `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- Upgrading cards, copies progress bars, `upgrade_card()`.
- Card detail / stats view, the encyclopedia screen (Deck/inventory button).
- Deck restriction rules (`DeckRules`), domain or synergy display.
- Removing a card to leave an empty slot, multiple decks, deck names, auto-fill, sorting/filter controls.
- Long-press pickup, custom touch drag handling, drag ghosts with art, animations, sounds.
- Styling/theming beyond default controls; new art; renaming the Heroes button.

## VERIFY

Static checks (run and report output):

1. `grep -rn "set_deck" --include=*.gd scripts/` — the definition in `PlayerProfile.gd` and exactly one call in `deck_overlay.gd`.
2. `grep -n "_draft_cards\[" scripts/ui/deck_overlay.gd` — writes occur only inside `_place()`.
3. `grep -n "\[connection" scenes/menu/deck_overlay.tscn` — no match.
4. `grep -n "DeckOverlay\|deck_overlay" scenes/menu/MainMenu.tscn scripts/ui/main_menu.gd` — the `ext_resource`, the instanced node, the `@onready`, two connects, two handlers.
5. `grep -n "_show_coming_soon.bind(\"Heroes\")" scripts/ui/main_menu.gd` — no match; `bind("Deck")` and `bind("Rewards")` still present.
6. `grep -n "_get_drag_data\|_can_drop_data\|_drop_data" scripts/ui/deck_tile.gd` — all three present.
7. `git status --short` — only the files named in sections 1–4.

Runtime checks (I run these in the Godot editor and on the phone — list them for me, do not claim them as done):

1. Main menu → Heroes: the screen shows Zeus on the far left and the 7 deck cards; nothing reacts to taps or drags; Close returns to the menu.
2. Edit: the pool appears with gods first, then cards; owned ones normal, locked ones grey; deck cards are marked "In deck".
3. Drag an owned card that is not in the deck onto a card slot: it replaces that slot. Drag one slot onto another: they swap. A card can never appear twice.
4. Tap a pool card, then tap a slot: same result as dragging.
5. A god cannot be placed on a card slot, a card cannot be placed on the god slot, and locked tiles can be neither selected nor dragged.
6. Cancel discards the changes. Save keeps them: reopen the screen and relaunch the game — the new deck is shown and `profile.json` matches.
7. Start a match: the hand cycles exactly the saved 7 cards, and the enemy AI mirrors them.
8. **On the phone:** scroll the pool with a finger, then try dragging a tile out of it. Report whether drag starts reliably or the pool scrolls instead (tap-then-tap must work either way).
