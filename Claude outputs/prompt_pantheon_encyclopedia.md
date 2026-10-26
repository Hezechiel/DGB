# Claude Code prompt — Pantheon Encyclopedia (Pantheon tab rebuild, step 1)

**Start in Plan Mode. Do not edit any file until I approve the plan.** In the plan, list every file you will create/modify and the node tree you will write into `pantheon_overlay.tscn`.

## Context

The Pantheon tab (`scenes/menu/pantheon_overlay.tscn` + `scripts/ui/pantheon_overlay.gd`, class `PantheonOverlay`) is a MainMenu tab page living inside `Background/MainContent` (offset_left 166, top 50, right -20, bottom -30 → ~984×460 at the 1170×540 viewport). Today it is a placeholder: grey `Panel`, one faction tab at a time, `GridContainer` with `columns = 8` of `DeckTile`s (`TILE_SIZE = 124×150`).

**Bug to fix first:** the page spills out of `MainContent` over the NavRail / FooterBar. Cause: 8 × 124 px tiles + separations (~1050 px) is wider than MainContent, and `Scroll` has `horizontal_scroll_mode = 0` (DISABLED), so the ScrollContainer reports the grid's full minimum width upward and the page grows past its anchors. The rebuild below must keep **every** container's minimum width at (or near) 0 so the page always fits MainContent — same principle as `FitCardGrid._get_minimum_size()` returning `Vector2.ZERO`.

Target look (art mockup, adapted): three framed blocks stacked vertically —
1. **Header panel** — emblem, "PANTHEON ENCYCLOPEDIA", subtitle, total owned count.
2. **Pantheon bar** — fixed `ALL` chip + horizontally pannable row of pantheon chips (multi-select).
3. **Main panel** — basic filter bar + vertical scroll of collapsible pantheon sections. Each section header = pantheon logo + "GREEK PANTHEON" + `owned / total` + chevron. Collapsed = first row of cards only; expanded = all cards of that pantheon.

All panels/subpanels use `ScaledNinePatch` (`scripts/ui/scaled_nine_patch.gd`) with `res://assets/menu/deck/frame_ninepatchrect.png` exactly like `DeckOverlay`'s `DeckPanel/Frame` (PanelContainer with `StyleBoxEmpty` → `Frame` ScaledNinePatch child + `Margin` MarginContainer child).

Existing resources to reference (uids taken from the project):
- `res://scripts/ui/scaled_nine_patch.gd` — `uid://c7kuqvyubxbjm`
- `res://assets/menu/deck/frame_ninepatchrect.png` — `uid://c30imutueoe3n` (152×127, patch margins 52/46/52/46)
- `res://assets/menu/deck/tab_active.png` — `uid://c4plb8sa3irt3`
- `res://assets/menu/deck/tab_inactive.png` — `uid://dwbbv8bcsprhg`
- Pantheon logos: `DeckCardTile.logo_for(faction)` (static, cached; `res://assets/menu/logos/logo_%s.png`; returns `null` if missing — only `logo_greek.png` exists today, so code MUST handle `null`).

---

## Step 1 — New file `scripts/ui/filter_chip.gd` (`class_name FilterChip`)

Small tap-only toggle chip, built in code (like `DeckCardTile`), used for ALL / pantheon chips / type tabs / owned toggle.

Why not `TextureButton` + `ButtonGroup` like the Deck tabs: the pantheon chips sit inside a horizontal `ScrollContainer`. A `TextureButton` with `mouse_filter = STOP` blocks swipe-panning; with `PASS` it still toggles on release after a swipe. So the chip does its own tap detection with the same rule as `DeckCardTile`/`DeckTile` (`TAP_MAX_DISTANCE = 10.0`, mouse events only — **do not** handle `InputEventScreenTouch`, or the tap fires twice).

```gdscript
extends Control
class_name FilterChip

# FilterChip — tapnutelny "chip" filtra (ALL, panteon, typ karty, Owned).
# Sam NIC nefiltruje — len hlasi tap; stav (active) nastavuje vlastnik.
# Vlastna detekcia tapu namiesto TextureButton: chip moze byt v horizontalnom
# ScrollContainer — swipe musi posuvat zoznam, nie prepinat chip.
# Tap-only toggle chip; the owner decides what "active" means.

signal tapped(chip: FilterChip)
```

Requirements:
- `mouse_filter = MOUSE_FILTER_PASS` (scroll parent must receive the drag).
- Children built in `_init()`: background `TextureRect` (full rect, `EXPAND_IGNORE_SIZE`, `STRETCH_SCALE`, `texture_filter = LINEAR_WITH_MIPMAPS`, mouse ignore), an `HBoxContainer` (centered, mouse ignore) holding an optional icon `TextureRect` (square, height-based, hidden when no texture) and a `Label` (outline 3, black outline, font size via export/const ~13).
- API: `setup(text: String, icon: Texture2D = null)`, `var key: StringName` (owner-defined payload), `var active: bool` with setter → swaps background `tab_active.png` / `tab_inactive.png` (preload both) and label color `TAB_ACTIVE_COLOR := Color(1.0, 0.85, 0.45)` / `TAB_INACTIVE_COLOR := Color(0.7, 0.72, 0.78)` (same values as `deck_overlay.gd`).
- `_get_minimum_size()` → width = label min width + icon + horizontal padding (~24 px), height = `custom_minimum_size.y` (owner sets e.g. 30). Must not depend on texture size.
- `_gui_input`: `InputEventMouseButton` left — remember press position on press; on release emit `tapped` only if `event.position.distance_to(press_pos) <= TAP_MAX_DISTANCE`. If the scroll steals the drag (no release arrives), reset on `NOTIFICATION_MOUSE_EXIT` / next press — no stuck state.

## Step 2 — New file `scripts/ui/wrap_card_grid.gd` (`class_name WrapCardGrid`, `@tool`, extends `Container`)

Fixed-column grid for use **inside a vertical ScrollContainer**: cell width comes from the available width, height from a callable, and the container reports a minimum height (so the scroll knows the content height) but **minimum width 0** (so it never pushes MainContent wider). `FitCardGrid` cannot be reused — it fits to height as well and reports min size 0×0, which inside a scroll collapses to nothing.

```gdscript
# WrapCardGrid — mriezka kariet s pevnym poctom stlpcov do VERTIKALNEHO scrollu.
# Sirka bunky = dostupna sirka / columns, vyska z cell_height_for_width
# (alebo card_aspect). Min. sirka je 0 (nikdy netlaci MainContent von),
# min. vyska = skutocna vyska riadkov (scroll vie, kolko obsahu ma).
# Neuplny posledny riadok je zarovnany VLAVO (encyklopedia, nie deck).
```

- Exports: `columns: int = 6` (min 1), `card_aspect: float = 0.82`, `h_separation: int = 8`, `v_separation: int = 8` — setters call `queue_sort()` + `update_minimum_size()`.
- `var cell_height_for_width: Callable` — if valid, `height = cell_height_for_width.call(width)`, else `width / card_aspect`.
- `_get_minimum_size()` → `Vector2(0, rows * cell_h + (rows - 1) * v_separation)` computed from current `size.x` (0 children → `Vector2.ZERO`).
- `_notification`: `NOTIFICATION_SORT_CHILDREN` → place children row-major, left-aligned, with `fit_child_in_rect(..., Rect2(pos.floor(), cell.floor()))`; `NOTIFICATION_RESIZED` → `update_minimum_size()` (height depends on width). Skip invisible / `top_level` / queued-for-deletion children (same filter as `FitCardGrid._sorted_items()`).
- Guard against `size.x <= 0` (first frame) — return a cell of width ≥ 1, no division by zero, no infinite resize loop.

## Step 3 — Small addition to `scripts/ui/deck_card_tile.gd`

Add only:
```gdscript
# Vyska dlazdice pre danu sirku — inverzia width_for_height (WrapCardGrid
# v encyklopedii ma sirku danu stlpcami).
static func height_for_width(width: float, card_aspect: float, with_progress: bool) -> float:
```
`card_h = width / card_aspect`; with progress: `(card_h + BAR_GAP) / (1.0 - BAR_RATIO)`. Return `maxf(1.0, …)`.

And update the header comment line `Pantheon tab dalej pouziva povodny DeckTile (KIND_* konstanty su zdielane odtial).` → state that the Pantheon tab now also uses `DeckCardTile` (non-draggable, with progress bar); `KIND_*` constants still live in `DeckTile`. **Nothing else in this file changes.**

## Step 4 — Rewrite `scenes/menu/pantheon_overlay.tscn`

Keep the scene uid (`uid://cyg2fjjf86dwy`), the root node name `PantheonOverlay`, the script ext_resource (`uid://dt28cm03cgvtj`) and the full-rect anchors of the root. Remove the old `Panel` subtree entirely. Follow the file/node format of `scenes/menu/deck_overlay.tscn` (Godot 4.7 writes a `unique_id=` on every node line — give every new node a unique random positive int that does not collide within this file).

Root: `mouse_filter = 2`, **`clip_contents = true`** (safety net — nothing may ever draw over the NavRail).

Static node tree (names matter — use `unique_name_in_owner = true` for nodes the script references, marked `%`):

```
PantheonOverlay (Control, full rect, clip_contents, script)
└── Layout (VBoxContainer, full rect, separation 6, mouse ignore)
    ├── HeaderPanel (PanelContainer, StyleBoxEmpty, custom_minimum_size.y = 58)
    │   ├── Frame (Control + ScaledNinePatch: frame texture, margins 52/46/52/46, patch_scale 0.6,
    │   │          fill_color Color(0.05,0.07,0.12,0.86), fill_inset 3, texture_filter 2, mouse ignore)
    │   └── Margin (MarginContainer 14/8/14/8)
    │       └── HeaderBox (HBoxContainer, separation 10)
    │           ├── %HeaderEmblem (TextureRect 44×44, expand_mode 1, stretch_mode 5, texture_filter 4, NO texture — asset comes later)
    │           ├── Titles (VBoxContainer, size_flags_horizontal 3, separation -2, alignment center)
    │           │   ├── TitleLabel  "PANTHEON ENCYCLOPEDIA" — gold Color(1,0.8,0.35), outline 5 Color(0.1,0.05,0), font 22
    │           │   └── SubtitleLabel "Discover the gods, heroes and mythical forces of the realms." — font 11, Color(0.85,0.85,0.9), text_overrun_behavior 3
    │           └── %TotalOwnedLabel (Label, right aligned, gold, font 16, outline 4) e.g. "34 / 48"
    ├── PantheonBar (HBoxContainer, custom_minimum_size.y = 32, separation 6)
    │   ├── %AllChipHolder (Control, custom_minimum_size 110×30) — script puts the ALL FilterChip here (full rect)
    │   └── %PantheonScroll (ScrollContainer, size_flags_horizontal 3, horizontal_scroll_mode = 3 (SHOW_NEVER), vertical_scroll_mode = 0, scroll_deadzone = 8)
    │       └── %PantheonChips (HBoxContainer, separation 6) — pantheon FilterChips built in code
    └── MainPanel (PanelContainer, StyleBoxEmpty, size_flags_vertical 3)
        ├── Frame (same ScaledNinePatch settings as HeaderPanel/Frame but patch_scale 0.7)
        └── Margin (MarginContainer 14/12/14/12)
            └── MainBox (VBoxContainer, separation 6)
                ├── FilterBar (HBoxContainer, custom_minimum_size.y = 30, separation 6)
                │   ├── TypeLabel "CARD TYPE" (font 12, gold, vertically centered)
                │   ├── %TypeChips (HBoxContainer, separation 4) — ALL / GODS / UNITS / SPELLS chips built in code
                │   ├── BarSpacer (Control, size_flags_horizontal 3, mouse ignore)
                │   └── %OwnedChipHolder (Control, custom_minimum_size 120×30) — "OWNED ONLY" chip
                └── %SectionsScroll (ScrollContainer, size_flags_vertical 3, horizontal_scroll_mode = 0, vertical_scroll_mode = 1 (AUTO), scroll_deadzone = 8)
                    └── %Sections (VBoxContainer, size_flags_horizontal 3, separation 8)
                    (+ %EmptyLabel (Label, hidden, centered) "No cards match these filters." as sibling of SectionsScroll or child of Sections — your choice, state it in the plan)
```

Every `Label` with dynamic text gets `text_overrun_behavior = 3` and must not contribute a large minimum width (`clip_text` / overrun) — this is the whole point of the fix.

## Step 5 — Rewrite `scripts/ui/pantheon_overlay.gd`

Keep: `extends Control`, `class_name PantheonOverlay`, `signal card_detail_requested(id: StringName, kind: StringName)`, the `activate()` / `deactivate()` tab contract, `visible = false` in `_ready()`, `PlayerProfile.profile_changed` refresh while visible, `_collect_factions()` logic (gods + cards with `obtain_source != 0`, sorted), `_by_cost_then_id()`. Update the header comment to describe the new layout. `main_menu.gd` must keep working unchanged.

### State (session-only, in memory — NOT saved to PlayerProfile, NOT reset in `activate()`)

```gdscript
enum TypeFilter { ALL, GODS, UNITS, SPELLS }
const CARD_ASPECT := 0.82          # rovnako ako deck_overlay.gd
@export var columns: int = 6       # karty v riadku (zbaleny panteon = 1 riadok)

var _selected: Dictionary = {}     # faction -> true; PRAZDNE = ALL (vsetky panteony)
var _type_filter: int = TypeFilter.ALL
var _owned_only: bool = false
var _expanded: Dictionary = {}     # faction -> bool
```

### Pantheon chip rules (multi-select)
- `ALL` chip is active iff `_selected.is_empty()`.
- Tap `ALL` → clear `_selected`.
- Tap a pantheon chip → toggle it in `_selected`. If that empties the set → back to ALL state.
- If **exactly one** pantheon ends up visible, it is shown expanded regardless of `_expanded` (single-pantheon view should show everything without an extra tap).
- Chip text = `String(faction).to_upper()`, icon = `DeckCardTile.logo_for(faction)` (may be null → text only).
- Chips are rebuilt in `activate()` (factions can only change with new data) and their `active` refreshed after every change. Built once per activate, not on every filter change.

### Type / owned chips
- Type chips: exactly one active (radio behaviour handled by the script, not a ButtonGroup).
- `GODS` shows only heroes, `UNITS` only `card.unit_data != null`, `SPELLS` only `card.spell_data != null`, `ALL` = gods first, then units, then spells (each group sorted like today: gods by id, cards `_by_cost_then_id`).
- `OWNED ONLY` chip toggles `_owned_only` → hide items the player doesn't own (`PlayerProfile.owns_hero` / `owns_card`).

### Sections (built in code into `%Sections`)
One section per faction in `_collect_factions()` order that is selected (or all when ALL) **and** has ≥ 1 item after type/owned filters. Sections with 0 items are skipped; if no section remains, show `%EmptyLabel`.

Per section (helper `_build_section(faction, ids_with_kinds) -> Control`):
```
SectionPanel (PanelContainer, StyleBoxEmpty)
├── Frame (ScaledNinePatch, same texture/margins, patch_scale 0.45, fill_color Color(0.08,0.10,0.16,0.9), fill_inset 3)
└── Margin (MarginContainer 10/8/10/8)
    └── Box (VBoxContainer, separation 6)
        ├── Header (PanelContainer, StyleBoxFlat bg Color(0,0,0,0.35) corner 4, custom_minimum_size.y 32, mouse_filter PASS)
        │   └── HBox: Logo (TextureRect 28×28, logo_for(faction), hidden if null) · NameLabel "GREEK PANTHEON" (gold, size_flags_h 3, overrun) · CountLabel "owned / total" · ChevronLabel "▼"/"▶"
        └── Grid (WrapCardGrid: columns = columns, card_aspect = CARD_ASPECT,
                  cell_height_for_width = func(w): return DeckCardTile.height_for_width(w, CARD_ASPECT, true))
```
- Header tap: own tap detection via `header.gui_input.connect(_on_section_header_input.bind(faction, header))` with the same `TAP_MAX_DISTANCE` press/release rule (no `Button` — a Button in the scroll would eat swipes or fire after them). Tap toggles `_expanded[faction]` and rebuilds.
- **CountLabel counts the whole pantheon** (all gods + obtainable cards of that faction, owned vs total) — it ignores type/owned filters so it's a stable collection-progress number.
- Collapsed → create tiles only for the first `columns` items. Expanded → all items. Chevron reflects state (hide the chevron and ignore taps when the pantheon has ≤ `columns` items after filtering — nothing to expand).
- Tiles: `DeckCardTile.new()`, `show_progress = true`, `draggable = false`, `setup(id, kind, -1)`, `tapped.connect(_on_tile_tapped)`. No `set_state` (not in-deck / not forbidden — locked state comes from `setup` itself). `_on_tile_tapped(tile: DeckCardTile)` → `card_detail_requested.emit(tile.item_id, tile.kind)`.

### Header total
`%TotalOwnedLabel` = owned / total across **all** pantheons (ignores every filter).

### Rebuild rules
- `_rebuild()` frees `%Sections` children (`remove_child` + `queue_free`, same as `deck_overlay._free_children`) and rebuilds.
- Rebuilds triggered by chip taps / header taps must be **deferred** (`call_deferred` with a `_rebuild_queued` guard, like `deck_overlay._queue_refresh()`), because the tap arrives from inside a child's `_gui_input`.
- Keep `%SectionsScroll.scroll_vertical` across a `profile_changed` rebuild and an expand/collapse rebuild (restore deferred after layout, like `deck_overlay._restore_pool_scroll`). Reset it to 0 when a pantheon/type/owned filter changes.

## Step 6 — `CLAUDE.md`

Update only the **Pantheon** bullet under "Menu screens" to describe: header panel, multi-select pantheon chips (ALL + pannable row), main panel with Type + Owned Only filters, collapsible per-pantheon sections (first row collapsed, all expanded, single selected pantheon auto-expanded), `DeckCardTile` tiles with progress bar, new helpers `FilterChip` / `WrapCardGrid`, filter state session-only. Also add `DeckCardTile.height_for_width()` mention where `DeckCardTile` is described if it fits naturally. Nothing else in CLAUDE.md.

---

## OUT OF SCOPE (do not implement)
- Rarity dropdown, energy-cost range slider, text search, sorting options — "robust filtering" comes later.
- Saving filter / expand state to `PlayerProfile` or disk.
- Any change to `CardDetail`, upgrades, packs, deck editing.
- Emblem / chip / chevron art — I supply assets later; leave `HeaderEmblem` texture empty and use text "▼"/"▶" for the chevron.
- Animated expand/collapse (tweens) — instant rebuild is fine for now.
- A canonical pantheon display order (art shows Greek, Norse, Egyptian, Babylonian) — keep alphabetical from `_collect_factions()`.
- Deleting `DeckTile` — it still holds `KIND_HERO` / `KIND_CARD` used everywhere; leave the file as is.

## DO NOT TOUCH
- `scenes/menu/MainMenu.tscn`, `scripts/ui/main_menu.gd` (the fix must live inside the Pantheon page itself)
- `scenes/menu/deck_overlay.tscn`, `scripts/ui/deck_overlay.gd`
- `scripts/ui/fit_card_grid.gd`, `scripts/ui/scaled_nine_patch.gd`, `scripts/ui/deck_tile.gd`
- `scripts/ui/deck_card_tile.gd` except the one static function + header comment in Step 3
- `scenes/menu/card_detail.tscn`, `scripts/ui/card_detail.gd`, `shop_overlay.*`
- All autoloads (`PlayerProfile`, `CardDB`, `BattleManager`, …), all `data/` resources, all `.import` files, `project.godot`
- `assets/` — no new or edited assets

## VERIFY

Static (grep):
1. `grep -n "DeckTile.new" scripts/ui/pantheon_overlay.gd` → no hits; `grep -n "DeckCardTile.new" scripts/ui/pantheon_overlay.gd` → 1 hit.
2. `grep -n "GridContainer" scripts/ui/pantheon_overlay.gd scenes/menu/pantheon_overlay.tscn` → no hits.
3. `grep -n "clip_contents = true" scenes/menu/pantheon_overlay.tscn` → root node has it.
4. `grep -n "horizontal_scroll_mode" scenes/menu/pantheon_overlay.tscn` → `PantheonScroll` = 3, `SectionsScroll` = 0.
5. `grep -rn "InputEventScreenTouch" scripts/ui/filter_chip.gd scripts/ui/pantheon_overlay.gd` → no hits.
6. `grep -n "func _get_minimum_size" scripts/ui/wrap_card_grid.gd scripts/ui/filter_chip.gd` → both present.
7. `grep -n "card_detail_requested" scripts/ui/main_menu.gd scripts/ui/pantheon_overlay.gd` → signal name/signature unchanged.
8. Project opens with no new errors/warnings in the Output panel; no parse errors in the 3 scripts.

Runtime (F5 → MainMenu, then Pantheon tab) — I will run these, list them in your final summary:
1. The whole page stays inside MainContent: nothing overlaps the NavRail, TopBar or FooterBar, at 1170×540 and after resizing the window narrower/wider.
2. Header panel, pantheon bar and main panel each show the ninepatch frame; section panels show a smaller frame inside the main panel.
3. `ALL` active on first open; every pantheon section listed, collapsed to one row of `columns` cards, chevron ▶.
4. Tap a section header → it expands to all its cards, chevron ▼; tap again → collapses. A vertical swipe that starts on a header scrolls and does NOT toggle it.
5. Tap `GREEK` → ALL turns inactive, only Greek shown, auto-expanded. Tap `GREEK` again → back to ALL. With 2+ pantheons selected (F10 grants all; Norse is WIP data) both sections show.
6. With more chips than fit (temporarily shrink the window if only 2 pantheons exist), the pantheon row pans horizontally by swipe; a swipe does not toggle a chip.
7. Type chips: GODS / UNITS / SPELLS / ALL filter tiles correctly; empty sections disappear; `OWNED ONLY` hides locked tiles; with F9 (reset profile) + OWNED ONLY + SPELLS → empty-state label if no spells owned.
8. Section `owned / total` and header total do NOT change when type/owned filters change; they DO change after F10 grant or a level-up.
9. Tap any tile (owned or locked) → CardDetail opens; upgrade a card there → close → tile progress/level updated, scroll position kept.
10. Switch to Deck tab and back → filter + expand state kept. Deck tab behaviour unchanged (tabs, edit mode, hold-to-drag).
