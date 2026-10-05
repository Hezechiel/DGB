# Claude Code prompt — Scrolls step 5e: synergy icon on the arena HUD + count in the deck editor

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 5d is merged (`BattleManager.get_synergy_status()` and `DeckRules.count_synergy_cards()` exist). If not, stop and tell me.

## Goal

1. **Arena HUD:** a small round icon near the card hand shows the player's synergy state — **greyed** when the deck threshold is not met, **glowing** when it is. Tapping it shows a tooltip with the count and the bonuses.
2. **Deck editor:** a line under the slot row shows the same rule with a **live count** (e.g. `Olympus 2 / 4`) that updates as cards are placed — this is where the player can act on it.
3. One shared, pure text builder so both places describe a rule identically.

The icon is a placeholder circle with a count; real art comes later. Synergy logic itself does not change. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. `scripts/deck_rules.gd` — one text builder

Append (keep everything already in the file):

```gdscript
# --- Synergy: text pre UI (HUD tooltip aj Deck obrazovka) ---

const _SYNERGY_UNIT_LABELS := {
	&"max_hp": "Health", &"damage": "Damage",
	&"speed": "Move speed", &"attack_speed": "Attack speed",
}

# Napr. "4 Olympus scrolls: Greek units +10% Health, +10% Damage".
# Prazdny string = boh nema synergy.
static func describe_synergy(hero: HeroData) -> String:
	if hero.synergy_tag == &"" or hero.synergy_count <= 0:
		return ""
	var pantheon := String(hero.faction).capitalize()
	var parts: Array[String] = []
	var unit_bits: Array[String] = []
	for key in _SYNERGY_UNIT_LABELS:
		if hero.synergy_bonuses.has(key):
			unit_bits.append("%s %s" % [_percent(hero.synergy_bonuses[key]), _SYNERGY_UNIT_LABELS[key]])
	if not unit_bits.is_empty():
		parts.append("%s units %s" % [pantheon, ", ".join(unit_bits)])
	if hero.synergy_bonuses.has(&"spell_damage"):
		parts.append("%s spells %s Damage" % [pantheon, _percent(hero.synergy_bonuses[&"spell_damage"])])
	if hero.synergy_bonuses.has(&"energy_regen"):
		parts.append("Energy regeneration %s" % _percent(hero.synergy_bonuses[&"energy_regen"]))
	return "%d %s scrolls: %s" % [hero.synergy_count, String(hero.synergy_tag).capitalize(), "; ".join(parts)]

static func _percent(mult: Variant) -> String:
	var pct := roundi((float(mult) - 1.0) * 100.0)
	return ("+%d%%" % pct) if pct >= 0 else ("%d%%" % pct)
```

## 2. New `scripts/arena/ui/synergy_icon.gd` + `scenes/arena/ui/SynergyIcon.tscn`

`class_name SynergyIcon`, `extends Button`. A `Button` is used on purpose: like the HUD's `TextureButton`s it consumes the touch itself, so a tap on it never falls through to tap-to-move in `arena.gd`.

Scene (keep it minimal — styles are built in code, no sub-resources):

```
SynergyIcon (Button, custom_minimum_size 56 x 56, focus_mode NONE, script)
├── CountLabel (Label, full rect, centred both ways, mouse_filter IGNORE)
└── Tooltip (PanelContainer, hidden, mouse_filter IGNORE)
    └── TooltipLabel (Label, autowrap WORD_SMART, custom_minimum_size.x = 280,
                      mouse_filter IGNORE)
```

Script:

```gdscript
# SynergyIcon — maly okruhly indikator synergy nad rukou. Sedy = podmienka
# balicka nie je splnena, zlaty a pulzujuci = splnena. Tap ukaze tooltip s
# poctom a bonusmi. Stav sa pocas zapasu NEMENI (zavisi len od balicka),
# preto staci jedno configure() po nastaveni manifestu v arena.gd.
# PLACEHOLDER vzhlad (kruh + cislo) — realny art pride neskor.

const INACTIVE_TINT := Color(0.45, 0.45, 0.45)
const ACTIVE_TINT := Color(1.0, 0.85, 0.35)
const TOOLTIP_SECONDS := 4.0
```

- `_ready()`: build one circular `StyleBoxFlat` (dark fill, `corner_radius_*` = 28, 2 px light border) and assign it to the `normal`, `hover`, `pressed`, `focus` and `disabled` style overrides; `visible = false`; `pressed.connect(_on_pressed)`.
- `configure(team: String) -> void`:
  - `var status := BattleManager.get_synergy_status(team)`. Empty → stay hidden, return.
  - `var hero := BattleManager.get_team_hero_data(team)` (the new helper in section 3); null → stay hidden, return.
  - `CountLabel.text = "%d/%d" % [status["have"], status["need"]]`.
  - Tooltip text, two lines: `"<Tag capitalised> <have> / <need> — active"` or `"… — not active"`, then `DeckRules.describe_synergy(hero)`.
  - **Tint only the circle and the count, never the tooltip:** use `self_modulate` on the button (it does not reach children) and the same colour on `CountLabel.modulate`. Not active → `INACTIVE_TINT`. Active → `ACTIVE_TINT`, plus a looping tween that pulses the button's `self_modulate` between `ACTIVE_TINT` and `ACTIVE_TINT.lightened(0.35)` (about 0.8 s each way). Kill any previous tween first.
  - `visible = true`.
- `_on_pressed()`: toggle the tooltip. When showing: `Tooltip.reset_size()`, then place it above the icon growing up and to the left — `Tooltip.position = Vector2(size.x - Tooltip.size.x, -Tooltip.size.y - 6.0)` — and start a `TOOLTIP_SECONDS` auto-hide (a token counter like `_toast_token` in `scripts/ui/main_menu.gd`, so a second tap does not get hidden by the first timer).
## 3. `scripts/BattleManager.gd` — one read helper

Next to `get_synergy_status()`:

```gdscript
# HeroData boha timu z manifestu (null ak tim nema manifest / neznamy boh).
func get_team_hero_data(team: String) -> HeroData:
	if not _manifests.has(team):
		return null
	var hero_id: StringName = _manifests[team]["hero_id"]
	return CardDB.get_hero(hero_id) if CardDB.has_hero(hero_id) else null
```

Nothing else in `BattleManager.gd` changes.

## 4. `scenes/hud/HUD.tscn` + `scripts/hud/HUD.gd`

- `HUD.tscn`: one `ext_resource` for `res://scenes/arena/ui/SynergyIcon.tscn` (by `path=` only) and one instanced node `SynergyIcon`, child of the root `HUD`, placed directly after the `EnergyBar` node, with `process_mode = 3` (same as `CardHand`). Anchor it bottom-right, just left of the hand's top-left corner, next to the energy bar:

```
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -452.0
offset_top = -176.0
offset_right = -396.0
offset_bottom = -120.0
grow_horizontal = 0
grow_vertical = 0
```

- `HUD.gd`: `@onready var synergy_icon: SynergyIcon = $SynergyIcon` after the `minimap` line (line 16). No other change.

## 5. `scripts/arena/arena.gd`

Directly after the synergy energy loop (the `for team in ["player", "enemy"]:` block that follows the two `set_team_manifest` calls), one line:

```gdscript
	hud.synergy_icon.configure("player")
```

This follows the existing `hud.minimap.configure_map(map_data)` pattern: the HUD's own `_ready()` runs before the manifests exist, so the arena hands the state over once.

## 6. `scripts/ui/deck_overlay.gd` — live count

- New `var _synergy_label: Label`, created in code in `_ready()` and inserted right under the slot row: `slot_row.add_sibling(_synergy_label)`. No `.tscn` change.
- New `_update_synergy_label()`, called at the end of `_rebuild()`:
  - `var hero: HeroData = CardDB.get_hero(_draft_hero) if CardDB.has_hero(_draft_hero) else null`. If `hero == null` or `DeckRules.describe_synergy(hero) == ""` → hide the label, return.
  - Build `Array[CardData]` from `_draft_cards`; `have = DeckRules.count_synergy_cards(hero, cards)`; `active = DeckRules.is_synergy_active(hero, cards)`.
  - Text: `"Synergy — %s %d / %d · %s" % [tag capitalised, have, hero.synergy_count, DeckRules.describe_synergy(hero)]`.
  - `modulate` gold (`Color(1.0, 0.85, 0.35)`) when active, grey (`Color(0.6, 0.6, 0.6)`) otherwise; visible in both view and edit mode.
- Nothing else in this file changes (placement, save, discard dialog, forbidden cards).

## DO NOT TOUCH

- Synergy logic: `DeckRules.count_synergy_cards`, `is_synergy_active`, `is_synergy_beneficiary`; in `BattleManager.gd` everything except the one new helper.
- `scripts/arena/ui/card_hand.gd`, `card.gd`, `energy_bar.gd`, `match_info_bar.gd`, `death_telegraph.gd`, `minimap.gd` and their scenes.
- `scenes/menu/deck_overlay.tscn`, `scripts/ui/deck_tile.gd`, `scripts/ui/encyclopedia_overlay.gd`, `scripts/ui/card_flashcard.gd`.
- `scripts/PlayerProfile.gd`, `scripts/MatchConfig.gd`, `scripts/EnergySystem.gd`, `scripts/ui/prematch_flow.gd`.
- In `HUD.tscn`: every existing node and offset.
- Everything under `data/` and `assets/`, `project.godot`, `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- Icon art, per-god icons, particles, sounds; anything beyond the placeholder circle and tint pulse.
- An icon for the enemy's synergy.
- Synergy text on the flashcard or in the encyclopedia.
- Closing the tooltip by tapping elsewhere (toggle + auto-hide only).
- Any change to how synergy is evaluated or applied; in-match conditions.
- Safe-area handling or responsive repositioning of HUD elements.

## VERIFY

Static checks (run and report output):

1. `grep -rn "describe_synergy" --include=*.gd scripts/` — defined in `deck_rules.gd`, used in `synergy_icon.gd` and `deck_overlay.gd` only.
2. `grep -n "get_node\|\$\|get_tree\|CardDB\|PlayerProfile\|BattleManager" scripts/deck_rules.gd` — no match (still pure).
3. `grep -n "SynergyIcon\|synergy_icon" scenes/hud/HUD.tscn scripts/hud/HUD.gd scripts/arena/arena.gd` — the `ext_resource`, the node, the `@onready`, one `configure("player")` call.
4. `grep -n "\[connection\|sub_resource" scenes/arena/ui/SynergyIcon.tscn` — no match.
5. `git diff scenes/menu/deck_overlay.tscn scripts/arena/ui/card_hand.gd scripts/PlayerProfile.gd` — empty.
6. `git diff scripts/BattleManager.gd` — only the added `get_team_hero_data()`.
7. `git status --short` — only `deck_rules.gd`, `synergy_icon.gd` + `SynergyIcon.tscn` (new), `BattleManager.gd`, `HUD.tscn`, `HUD.gd`, `arena.gd`, `deck_overlay.gd`.

Runtime checks (I run these in the Godot editor and on the phone — list them for me, do not claim them as done):

1. Untouched data, Zeus deck: in a match the icon sits left of the hand next to the energy bar, grey, showing `0/4`. It does not overlap the hand, the energy bar or the minimap.
2. Tap the icon: the tooltip appears above it with `Olympus 0 / 4 — not active` and `4 Olympus scrolls: Greek units +10% Health, +10% Damage`; it is fully on screen and readable; it hides on a second tap or after about 4 seconds. The hero does **not** walk toward the tapped spot.
3. Temporarily mark four deck cards `domain = olympus` in the Inspector: the icon is gold and pulsing with `4/4`, tooltip says `active`.
4. Pause the game from the HUD: the icon stays put and nothing errors.
5. Deck screen (Heroes button): under the slots a grey line reads `Synergy — Olympus 0 / 4 · 4 Olympus scrolls: …`. With the temporary Olympus cards, enter Edit and place them one by one: the count rises live and the line turns gold at 4. Swap one out: back to grey.
6. Switch the god to Poseidon in the editor: the line switches to his rule (`Sea …`).
7. Revert the temporary `.tres` edits.
8. **On the phone:** the icon is big enough to tap and is not hidden under a thumb holding a card.
