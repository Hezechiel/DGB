# Claude Code prompt — Scrolls step 4: packs, pack roller, Shop screen

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 3 is merged (`BattleManager.set_team_manifest` exists). If not, stop and tell me.

## Goal

The player opens free scroll packs from the main menu's Shop button, and the rolled cards are added to the profile.

1. `PackData` resource + two pack `.tres` files.
2. `PackRoller` — a pure static roller (no nodes, no autoloads): same contract as `EnergySystem`, server-portable.
3. `CardDB` loads packs and builds the drop pool.
4. A `ShopOverlay` on the main menu: list of packs → open → list reveal.

Rarity codes (already in the project): `0` COMMON, `1` RARE, `2` EPIC, `3` LEGENDARY, `4` UNIQUE (gods). Only content with `obtain_source == 1` (PACK) can drop. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. New file `scripts/pack_data.gd`

```gdscript
extends Resource
class_name PackData

# PackData — definicia jedneho balicka zvitkov. Cisla su PLACEHOLDER a
# ladia sa v .tres. Vahy rarit su PER BALICEK: lacne balicky maju UNIQUE
# (bohovia) na 0, sancu davaju len "cherished" balicky a eventy.

@export var id: StringName
@export var display_name: String
@export var card_count: int = 5
# Filter panteonu. &"" = bez filtra.
@export var faction: StringName = &"greek"
# Vahy podla rarity, index = rarity kod (0 COMMON .. 4 UNIQUE). Dlzka 5.
# Nemusia davat sucet 100 — su relativne.
@export var rarity_weights: PackedFloat32Array
# POSLEDNY slot balicka ma zarucenu aspon tuto raritu. 0 = bez garancie.
@export var guaranteed_min_rarity: int = 1
# Cena — zatial vzdy 0, mena este neexistuje.
@export var price: int = 0
```

## 2. New files `data/packs/greek_scroll_pack.tres` and `data/packs/greek_cherished_pack.tres`

| Field | `greek_scroll_pack` | `greek_cherished_pack` |
|---|---|---|
| `id` | `&"greek_scroll_pack"` | `&"greek_cherished_pack"` |
| `display_name` | `"Greek Scroll Pack"` | `"Cherished Greek Pack"` |
| `card_count` | 5 | 5 |
| `faction` | `&"greek"` | `&"greek"` |
| `rarity_weights` | 70, 22, 6, 2, 0 | 50, 30, 13, 5, 2 |
| `guaranteed_min_rarity` | 1 | 2 |
| `price` | 0 | 0 |

Reference the script by `path=` only (no invented uid), same as `data/progression/level_curve.tres`.

## 3. New file `scripts/pack_roller.gd`

```gdscript
extends RefCounted
class_name PackRoller

# PackRoller — cista matematika, ziadne nody ani autoloady. Pool prichadza
# ako argument (rarity kod -> zoradene pole id-ciek), RNG tiez — server
# neskor zavola presne toto. Duplikaty v jednom balicku su povolene.

const RARITY_COUNT := 5

static func roll(pack: PackData, rng: RandomNumberGenerator, pool: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for i in pack.card_count:
		# garancia sedi na POSLEDNOM slote (vyvrcholenie reveal-u)
		var min_rarity := 0
		if i == pack.card_count - 1:
			min_rarity = maxi(0, pack.guaranteed_min_rarity)
		var rarity := _pick_rarity(pack.rarity_weights, min_rarity, rng)
		var ids := _resolve_pool(pool, rarity, pack.rarity_weights)
		if ids.is_empty():
			continue
		result.append(ids[rng.randi_range(0, ids.size() - 1)])
	return result

# Vazeny vyber rarity >= min_rarity. Ak su vsetky take vahy 0, vrati min_rarity
# (o realnom obsahu aj tak rozhodne _resolve_pool).
static func _pick_rarity(weights: PackedFloat32Array, min_rarity: int, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in range(min_rarity, RARITY_COUNT):
		total += _weight(weights, r)
	if total <= 0.0:
		return min_rarity
	var roll_value := rng.randf() * total
	for r in range(min_rarity, RARITY_COUNT):
		roll_value -= _weight(weights, r)
		if roll_value <= 0.0:
			return r
	return RARITY_COUNT - 1

# Ak vylosovana rarita nema ziadny obsah, padne na najblizsiu NIZSIU, potom
# na najblizsiu VYSSIU. Rarita s vahou 0 sa NIKDY nepouzije ako nahrada —
# balicek s UNIQUE = 0 tak nikdy nevyda boha, ani ked su ostatne pooly prazdne.
static func _resolve_pool(pool: Dictionary, rarity: int, weights: PackedFloat32Array) -> Array:
	if _usable(pool, rarity, weights):
		return pool[rarity]
	for r in range(rarity - 1, -1, -1):
		if _usable(pool, r, weights):
			return pool[r]
	for r in range(rarity + 1, RARITY_COUNT):
		if _usable(pool, r, weights):
			return pool[r]
	return []

static func _usable(pool: Dictionary, rarity: int, weights: PackedFloat32Array) -> bool:
	return _weight(weights, rarity) > 0.0 and pool.has(rarity) and not pool[rarity].is_empty()

static func _weight(weights: PackedFloat32Array, rarity: int) -> float:
	return weights[rarity] if rarity >= 0 and rarity < weights.size() else 0.0
```

Use this code as given.

## 4. `scripts/CardDB.gd` — packs and the drop pool

- Add `const PACKS_PATH := "res://data/packs/"`, `var _packs: Dictionary = {}`, and a fifth `_scan_into(PACKS_PATH, _packs)` in `_ready()`. The existing scan/duplicate-id code handles `PackData` unchanged (it has an `id`).
- Add:

```gdscript
func get_pack(id: StringName) -> PackData:
	if not _packs.has(id):
		push_error("CardDB: unknown pack id '%s'" % id)
		return null
	return _packs[id]

# Zoradene (deterministicke poradie nezavisle od poradia suborov na disku).
func list_pack_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_packs.keys())
	ids.sort()
	return ids

# Drop pool pre PackRoller: rarity kod -> ZORADENE pole id-ciek. Obsahuje
# karty AJ bohov s obtain_source == 1 (PACK). faction &"" = bez filtra.
func get_pack_pool(faction: StringName) -> Dictionary:
	var pool: Dictionary = {}
	for source in [_cards, _heroes]:
		for id in source:
			var res = source[id]
			if res.obtain_source != 1:
				continue
			if faction != &"" and res.faction != faction:
				continue
			if not pool.has(res.rarity):
				pool[res.rarity] = []
			pool[res.rarity].append(id)
	for rarity in pool:
		pool[rarity].sort()
	return pool
```

- Update the header comment to mention packs.

## 5. New `scripts/ui/shop_overlay.gd` + `scenes/menu/shop_overlay.tscn`

Follow the existing overlay pattern in `scripts/ui/credits_overlay.gd` / `scenes/menu/credits_overlay.tscn` (fullscreen `Control`, hidden by default, `open()` / `close()`, `closed` signal). Keep the scene tree small — plain Godot controls, no art assets, default theme:

```
ShopOverlay (Control, full rect, script shop_overlay.gd)
└── ShopPanel (Panel, full rect)
    └── Margin (MarginContainer, full rect, 24 px margins)
        └── Content (VBoxContainer)
            ├── Header (HBoxContainer)
            │   ├── TitleLabel (Label, text "Shop", expand)
            │   └── CloseButton (Button, text "Close")
            ├── PackList (VBoxContainer)              — filled in code
            └── RevealBox (VBoxContainer, hidden)
                ├── RevealTitle (Label)
                ├── RevealScroll (ScrollContainer, expand vertical)
                │   └── RevealList (HBoxContainer)    — filled in code
                └── RevealOkButton (Button, text "OK")
```

`shop_overlay.gd` (`class_name ShopOverlay`, `signal closed`):

- `_ready()`: `visible = false`; connect `CloseButton.pressed` → `close()` and `RevealOkButton.pressed` → back to the pack list. **Code-based connections only**, no Inspector wiring.
- `open()`: rebuild `PackList` — one `Button` per id from `CardDB.list_pack_ids()`, text `"%s — %d scrolls — FREE"` (use `"%d"` price instead of FREE when `price > 0`), `custom_minimum_size.y = 56`; show `PackList`, hide `RevealBox`; `visible = true`.
- `close()`: `visible = false`; `closed.emit()`.
- `_open_pack(pack_id: StringName)`:
  1. `var pack := CardDB.get_pack(pack_id)`; return if null.
  2. `var rng := RandomNumberGenerator.new()`, `rng.randomize()`.
  3. `var rolled := PackRoller.roll(pack, rng, CardDB.get_pack_pool(pack.faction))`.
  4. **Before granting**, record for each rolled id whether it is new (`not PlayerProfile.owns_card(id) and not PlayerProfile.owns_hero(id)`); an id rolled twice in one pack is new only the first time.
  5. `PlayerProfile.grant_cards(rolled)` — one call for the whole pack.
  6. `print("[pack] %s -> %s" % [pack_id, rolled])`.
  7. Fill `RevealList`: per rolled id one `VBoxContainer` with a `TextureRect` (`custom_minimum_size = Vector2(120, 144)`, `expand_mode = EXPAND_IGNORE_SIZE`, `stretch_mode = STRETCH_KEEP_ASPECT_CENTERED`; texture = `CardData.scroll_texture` for cards, left empty for gods — they have no scroll art yet), a name `Label` (`display_name`), a rarity `Label` (`Common` / `Rare` / `Epic` / `Legendary` / `Unique`) and a status `Label`: `"NEW"` or `"+1 copy"`. Clear previous children with `queue_free()` first.
  8. `RevealTitle.text = pack.display_name`; hide `PackList`, show `RevealBox`.
- If `rolled` is empty (no obtainable content), show `RevealTitle.text = "Nothing to reveal"` with an empty list instead of crashing.

## 6. `scripts/ui/main_menu.gd` + `scenes/menu/MainMenu.tscn`

`MainMenu.tscn`: add one `ext_resource` for `res://scenes/menu/shop_overlay.tscn` (by `path=` only) and one instanced node `ShopOverlay` as a child of the root `MainMenu`, placed right after `CreditsOverlay`, with `visible = false`. Nothing else in the scene changes.

`main_menu.gd`:

- `@onready var shop_overlay: ShopOverlay = $ShopOverlay`.
- Replace line 48 (`shop_button.pressed.connect(_show_coming_soon.bind("Shop"))`) with `shop_button.pressed.connect(_on_shop_button_pressed)`, and add `shop_overlay.closed.connect(_on_shop_overlay_closed)`.
- Two handlers, mirroring the credits ones (lines 83–88 and 97–99):

```gdscript
func _on_shop_button_pressed() -> void:
	nav_rail.visible = false
	main_content.visible = false
	shop_overlay.move_to_front()
	shop_overlay.open()

func _on_shop_overlay_closed() -> void:
	nav_rail.visible = true
	main_content.visible = true
```

The Deck, Heroes and Rewards buttons keep their "coming soon" toast.

## DO NOT TOUCH

- `scripts/PlayerProfile.gd` (use only its existing `owns_card`, `owns_hero`, `grant_cards`).
- `scripts/BattleManager.gd`, `scripts/MatchConfig.gd`, `scripts/EnergySystem.gd`, `scripts/level_curve.gd`, `scripts/ui/prematch_flow.gd`.
- Everything under `scripts/arena/`, including `ui/card.gd` and `Card.tscn` (the reveal does **not** reuse the in-match `Card` scene — it is wired to `CardHand` drag input).
- `data/cards/`, `data/units/`, `data/heroes/`, `data/spells/`, `data/progression/`, `assets/`.
- `scenes/menu/setting_overlay.tscn`, `scenes/menu/credits_overlay.tscn` and their scripts.
- `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- Currency, prices above 0, purchase confirmation, the top-bar currency label.
- Pack-opening animation, card flip, sounds, particles — the reveal is a plain list.
- Collection screen, deck editing, upgrades, level display.
- Pity timers, duplicate protection, daily limits, pack inventory, event packs.
- Server-side or seeded/replayable rolling; the client rolls with `randomize()`.
- Styling/theming of the overlay beyond default controls; new art assets.
- Changing rarities or `obtain_source` of any card or god.

## VERIFY

Static checks (run and report output):

1. `grep -n "get_node\|\$\|get_tree\|CardDB\|PlayerProfile\|randomize" scripts/pack_roller.gd` — no match (pure, no autoloads).
2. `grep -rn "PackRoller.roll" --include=*.gd scripts/` — only `scripts/ui/shop_overlay.gd`.
3. `grep -rn "grant_cards" --include=*.gd scripts/` — only `PlayerProfile.gd` (definition/internal) and one call in `shop_overlay.gd`.
4. `grep -n "\[connection" scenes/menu/shop_overlay.tscn` — no match (no Inspector-wired signals).
5. `grep -n "ShopOverlay\|shop_overlay" scenes/menu/MainMenu.tscn scripts/ui/main_menu.gd` — the `ext_resource`, the instanced node, the `@onready`, two connects, two handlers.
6. `grep -n "_show_coming_soon.bind(\"Shop\")" scripts/ui/main_menu.gd` — no match.
7. Both pack `.tres` files: `rarity_weights` has exactly 5 entries; the basic pack's last entry is `0`.
8. `git status --short` — only the files named in sections 1–6.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. Project opens with no `CardDB` `push_error`.
2. Main menu → Shop: the overlay lists both packs; Close returns to the menu with the nav rail and battle button back.
3. Open "Greek Scroll Pack": 5 scrolls are revealed, the last one is Rare (never Common); the console prints the `[pack]` line; no god ever appears from this pack (open it ~20 times).
4. A card you did not own (Sphendonetes, Phalanx, Priestess, Ensnaring Net) shows `NEW` the first time and `+1 copy` afterwards; `profile.json` shows it owned at level 1 and copies counting up.
5. Open "Cherished Greek Pack" repeatedly: Zeus (`+1 copy`) or Poseidon (`NEW` once) appears occasionally (roughly 1 pack in 6).
6. Relaunch: owned cards and copies persist.
7. Start a match afterwards: it plays as before (the deck is still the 7 starter cards).
