# Claude Code prompt — Scrolls step 5b: Encyclopedia, card flashcard, level up

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 5a is merged (`scripts/ui/deck_tile.gd`, `scripts/ui/deck_overlay.gd` and `CardDB.list_card_ids()` exist). If not, stop and tell me.

## Goal

1. The main menu's **Deck** (inventory icon) button opens an **Encyclopedia**: every god and card of a pantheon, owned and locked.
2. Tapping any tile there opens a **flashcard** — a detail panel with the art, level, copies progress, description and battle stats (SWFA unit-detail style), with a "current > next level" preview for the stats that scale.
3. The flashcard has a **Level up** button. Leveling is **manual**: it spends copies and raises the level by one. Nothing levels automatically.

The flashcard is built as its own scene so other screens can open it later; in this step **only the Encyclopedia opens it**. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. Data: a description field

`scripts/arena/ui/card_data.gd` and `scripts/arena/hero_data.gd` — add to the Scrolls metadata block of each:

```gdscript
# Kratky popis pre flashcard (encyklopedia). Prazdny = nic sa nezobrazi.
@export_multiline var description: String = ""
```

Do not write descriptions into any `.tres` — the texts are authored later.

## 2. `scripts/PlayerProfile.gd` — the upgrade API

Add near the other constants:

```gdscript
# Ladiace cisla progresie (kopie na level, nasobice). Rovnaky resource ako
# BattleManager.LEVEL_CURVE — cisto data, ziadna scena.
const LEVEL_CURVE: LevelCurve = preload("res://data/progression/level_curve.tres")
```

Add to the read API:

```gdscript
# Kolko kopii treba na dalsi level. -1 = nevlastnene, neznamy id alebo max level.
func get_copies_to_next(id: StringName) -> int:
	if CardDB.has_card(id) and _cards.has(id):
		return LEVEL_CURVE.copies_to_next(CardDB.get_card(id).rarity, _cards[id]["level"])
	if CardDB.has_hero(id) and _heroes.has(id):
		return LEVEL_CURVE.copies_to_next(CardDB.get_hero(id).rarity, _heroes[id]["level"])
	return -1

func can_upgrade(id: StringName) -> bool:
	var need := get_copies_to_next(id)
	if need < 0:
		return false
	var copies: int = get_card_copies(id) if _cards.has(id) else get_hero_copies(id)
	return copies >= need
```

Add to the mutation API (works for cards and gods, like `grant_cards`):

```gdscript
# Manualny level up: minie kopie a zdvihne level o 1. Jedine miesto, kde sa
# level meni. Vrati false (a nic nezmeni), ak sa upgradovat neda.
func upgrade_card(id: StringName) -> bool:
	if not can_upgrade(id):
		return false
	var need := get_copies_to_next(id)
	var entry: Dictionary = _cards[id] if _cards.has(id) else _heroes[id]
	entry["copies"] -= need
	entry["level"] += 1
	save_profile()
	profile_changed.emit()
	return true
```

Update the header comment that lists the mutation API to include `upgrade_card()`. Nothing else in this file changes.

## 3. `scripts/ui/deck_tile.gd` — three small additions for reuse

The Encyclopedia reuses `DeckTile`. Add, without changing existing behaviour for the Deck screen (all three default to today's behaviour):

- `var allow_locked_tap: bool = false` — in `_gui_input`, the tap condition on line 112 becomes `interactive and (not locked or allow_locked_tap) and ...`.
- `var draggable: bool = true` — `_get_drag_data()` (line 116) also returns `null` when `not draggable`.
- A generic note next to `set_in_deck()`:

```gdscript
# Volitelna poznamka za zakladnym textom (napr. "3/4", "Ready", "MAX").
func set_note(text: String) -> void:
	_info_label.text = _base_info + (" · " + text if text != "" else "")
```

Update the class comment (lines 4–6) to say the tile is also used by the Encyclopedia.

## 4. New `scripts/ui/card_flashcard.gd` + `scenes/menu/card_flashcard.tscn`

`class_name CardFlashcard`, `extends Control`, `signal closed`. A modal panel: a full-rect dim background plus a centred panel. Scene tree (plain controls, default theme, no art):

```
CardFlashcard (Control, full rect, hidden)
├── Dim (ColorRect, full rect, Color(0, 0, 0, 0.6), mouse_filter STOP)
└── Card (PanelContainer, centred, custom_minimum_size 900 x 470)
    └── Margin (MarginContainer, 16 px)
        └── Layout (HBoxContainer)
            ├── Left (VBoxContainer, min width 220)
            │   ├── Picture (TextureRect, min size 200 x 240, EXPAND_IGNORE_SIZE,
            │   │            STRETCH_KEEP_ASPECT_CENTERED)
            │   ├── LevelLabel (Label)
            │   ├── CopiesBar (ProgressBar, show_percentage off)
            │   ├── CopiesLabel (Label)
            │   └── LevelUpButton (Button, min height 56)
            └── Right (VBoxContainer, expand)
                ├── Header (HBoxContainer)
                │   ├── NameLabel (Label, expand)
                │   └── CloseButton (Button, "X")
                ├── MetaLabel (Label)            — "Squad · Rare · Cost 5"
                ├── DescriptionLabel (Label, autowrap)
                └── StatsGrid (GridContainer, columns = 3) — filled in code
```

Script:

```gdscript
# Text tlacidla na jednom mieste — tematicky nazov sa vyberie neskor.
const LEVEL_UP_LABEL := "Level up"
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Unique"]
```

- `_ready()`: `visible = false`; code-based connections: `CloseButton.pressed` → `close()`, `LevelUpButton.pressed` → `_on_level_up_pressed()`.
- `open_for(id: StringName, kind: StringName) -> void` (`kind` uses `DeckTile.KIND_HERO` / `DeckTile.KIND_CARD`): store both, call `_refresh()`, `visible = true`.
- `close()`: `visible = false`; `closed.emit()`.
- `_on_level_up_pressed()`: `if PlayerProfile.upgrade_card(_id): _refresh()`.
- `_refresh()` fills everything from `CardDB` + `PlayerProfile`:
  - **Owned state:** `owned`, `level` (1 when not owned, for display), `need = PlayerProfile.get_copies_to_next(id)`, `copies`.
  - **Picture / name / description:** card → `scroll_texture`, `display_name`, `description`; god → first frame of `&"iddle_left"` then `&"idle_left"` (same guard as `DeckTile._hero_texture`), `display_name`, `description`. Hide `DescriptionLabel` when the text is empty.
  - **MetaLabel:** `"<type> · <rarity> · Cost <n>"`. Type: `God`; `Spell`; `Squad` when `unit_count > 1`; else `Unit`. Gods have no cost — omit that part.
  - **LevelLabel:** `"Locked"` or `"Lv %d"`.
  - **Copies:** not owned → bar hidden, `CopiesLabel` empty. Max level (`need < 0` and owned) → bar full, label `"MAX"`. Otherwise bar `max_value = need`, `value = min(copies, need)`, label `"%d / %d" % [copies, need]`.
  - **LevelUpButton:** `text = LEVEL_UP_LABEL`; visible only when owned and not at max level; `disabled = not PlayerProfile.can_upgrade(id)`.
  - **Stats:** clear `StatsGrid` (`queue_free()`), then one `Label` per stat, text `"<Name>: <value>"`.

Stat values. Use `var curve := PlayerProfile.LEVEL_CURVE`. A **scaling** stat shows `"cur > next"` when owned and below max level, otherwise just `cur`:

```
cur  = roundi(base * curve.get_stat_multiplier(level))
next = roundi(base * curve.get_stat_multiplier(level + 1))
```

This is the same formula `unit.gd` / `player.gd` / `spell_zone.gd` apply in a match — keep it identical.

| Kind | Stats, in this order |
|---|---|
| Unit card (`unit_data`) | **Health** (scaling, `max_hp`) · **Damage** (scaling, `damage`) · Attack cooldown `"%.1fs"` · Move speed · Range · Attack (`Melee` / `Ranged` from `attack_type`) · Target (`All` / `Units` / `Structures` — map from the `TargetFilter` enum in `scripts/arena/unit.gd`; confirm the order there) · Squad size (`unit_count`, only when > 1) |
| Spell card (`spell_data`) | **Damage** (scaling, only when `damage > 0`) · Radius · Cast time `"%.1fs"` · Zone duration `"%.1fs"` (only when > 0) · Effect duration `"%.1fs"` |
| God | **Health** (scaling, `max_hp`) · **Damage** (scaling, `projectile_damage`) · **Attack recovery** (scaling the other way: `recovery_time / curve.get_hero_attack_speed_multiplier(level)`, `"%.2fs"`) · Move speed · Range · Domain (omit when empty) |

Move speed, range, durations, radius and cooldown never show a preview — they do not scale with level.

## 5. New `scripts/ui/encyclopedia_overlay.gd` + `scenes/menu/encyclopedia_overlay.tscn`

`class_name EncyclopediaOverlay`, same overlay pattern as `DeckOverlay` (`open()` / `close()`, `signal closed`, code-based connections).

```
EncyclopediaOverlay (Control, full rect)
├── Panel (Panel, full rect)
│   └── Margin (MarginContainer, 16 px)
│       └── Content (VBoxContainer)
│           ├── Header (HBoxContainer)
│           │   ├── TitleLabel (Label, "Encyclopedia", expand)
│           │   ├── OwnedLabel (Label)                 — "Owned 8 / 13"
│           │   └── CloseButton (Button, "Close")
│           ├── FactionTabs (HBoxContainer)            — one Button per pantheon, built in code
│           └── Scroll (ScrollContainer, expand vertical, horizontal scroll disabled)
│               └── Sections (VBoxContainer)           — built in code
└── Flashcard (instance of card_flashcard.tscn)        — last child, draws on top
```

Behaviour:

- `open()`: collect the pantheons = distinct `faction` values over every god and every card with `obtain_source != 0`, sorted; build one toggle-style `Button` per pantheon (text = capitalised faction id); select the first; rebuild; `visible = true`.
- **Sections** for the selected pantheon, in this order, each a heading `Label` plus a `GridContainer` (columns = 8) of `DeckTile`s: **Gods**, **Units** (cards with `unit_data`), **Spells** (cards with `spell_data`). Skip a section with no entries. Cards with `obtain_source == 0` never appear. Order inside a section: `cost`, then id (gods: id).
- Each tile: `setup(id, kind, -1)`, then `interactive = true`, `allow_locked_tap = true`, `draggable = false`. Note via `set_note()`: owned and upgradable → `"Ready"`; owned at max level → `"MAX"`; owned otherwise → `"%d/%d" % [copies, need]`; locked → no note.
- `tapped` → `flashcard.open_for(tile.item_id, tile.kind)`.
- `OwnedLabel`: owned count / total count of what is listed for the selected pantheon.
- Self-subscribe in `_ready()`: `PlayerProfile.profile_changed.connect(_on_profile_changed)` → rebuild the sections when the overlay is visible (so a level up updates the tile behind the flashcard).
- `close()`: close the flashcard if open; `visible = false`; `closed.emit()`.
- Free old tiles with `queue_free()` when rebuilding.

## 6. `scripts/ui/main_menu.gd` + `scenes/menu/MainMenu.tscn`

Mirror exactly how `DeckOverlay` is wired:

- `MainMenu.tscn`: one `ext_resource` for `res://scenes/menu/encyclopedia_overlay.tscn` (by `path=` only) and one instanced node `EncyclopediaOverlay` directly after the `DeckOverlay` node (line 61), written the same way. No `[connection]` entries.
- `main_menu.gd`: `@onready var encyclopedia_overlay: EncyclopediaOverlay = $EncyclopediaOverlay` after the `deck_overlay` one; replace `deck_button.pressed.connect(_show_coming_soon.bind("Deck"))` with `deck_button.pressed.connect(_on_deck_button_pressed)`; add `encyclopedia_overlay.closed.connect(_on_encyclopedia_overlay_closed)`; two handlers with the same shape as `_on_heroes_button_pressed()` / `_on_deck_overlay_closed()`.
- The variable keeps the name `deck_button`. Rewards, Mail and Gift keep their toast.

## DO NOT TOUCH

- `scripts/ui/deck_overlay.gd`, `scenes/menu/deck_overlay.tscn` (the Deck screen does not open the flashcard in this step).
- `scripts/ui/shop_overlay.gd`, `scripts/pack_roller.gd`, `scripts/pack_data.gd`, `scripts/CardDB.gd`, `scripts/level_curve.gd`.
- `scripts/BattleManager.gd`, `scripts/MatchConfig.gd`, `scripts/ui/prematch_flow.gd`, everything under `scripts/arena/` except the single `description` export in `ui/card_data.gd` and `hero_data.gd`.
- In `PlayerProfile.gd`: save/load, starter grant, `grant_cards`, `set_deck`, `reset_profile`.
- Everything under `data/` and `assets/`, `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- Opening the flashcard from the Deck screen, the shop reveal or the match.
- Currency or any upgrade cost other than copies; player XP / account level; upgrade rewards.
- Auto-leveling, "upgrade all", level-up animation, sounds, confirmation dialogs.
- SWFA-style tabs (Details, Advantages), damage-per-second, deployment time, synergy display.
- Search, sorting or filter controls; pantheons other than those found in the data.
- Deck restriction rules (`DeckRules`).
- Writing description texts; styling beyond default controls; new art.

## VERIFY

Static checks (run and report output):

1. `grep -rn "upgrade_card" --include=*.gd scripts/` — the definition in `PlayerProfile.gd` and exactly one call, in `card_flashcard.gd`.
2. `grep -n "\[\"level\"\] +=\|\[\"level\"\] =" scripts/PlayerProfile.gd` — the level is raised only inside `upgrade_card()` (plus the existing load/grant initialisation).
3. `grep -rn "open_for" --include=*.gd scripts/` — defined in `card_flashcard.gd`, called only from `encyclopedia_overlay.gd`.
4. `grep -n "\[connection" scenes/menu/encyclopedia_overlay.tscn scenes/menu/card_flashcard.tscn` — no match.
5. `git diff scripts/ui/deck_overlay.gd scenes/menu/deck_overlay.tscn` — empty.
6. `grep -n "allow_locked_tap\|draggable\|set_note" scripts/ui/deck_tile.gd` — all three present, both vars defaulting to today's behaviour (`false` / `true`).
7. `grep -n "_show_coming_soon.bind(\"Deck\")" scripts/ui/main_menu.gd` — no match; `bind("Rewards")` still present.
8. `grep -rn "description = " data/` — no match (no texts written).
9. `git status --short` — only the files named in sections 1–6.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. Main menu → Deck (inventory icon): the Encyclopedia shows a Greek tab with Gods, Units and Spells; owned tiles normal, locked ones grey; the owned counter is right.
2. Tap a locked card: the flashcard opens with "Locked", level-1 stats, no copies bar and no level-up button.
3. Tap an owned card without enough copies: copies bar e.g. `0 / 2`, button disabled, Health and Damage show `cur > next`.
4. Open packs in the Shop until a Common card has 2 copies: its tile says "Ready"; on the flashcard the button is enabled. Press it: level becomes 2, copies drop by 2, the stats shift (Hoplite Health `150 > 162` becomes `162 > 173`), and the tile behind updates.
5. `profile.json` shows the new level and copies; they persist after a relaunch.
6. Start a match with that card in the deck: its `[spawn]` line shows the new level.
7. A god's flashcard shows Health, Damage and Attack recovery with previews; a spell shows Damage with a preview and durations without.
8. Edit `profile.json` to put a card at level 10: the flashcard shows `MAX`, no preview and no button.
9. The Deck screen (Heroes button) still works exactly as before: drag, tap-then-tap, locked tiles not selectable.
