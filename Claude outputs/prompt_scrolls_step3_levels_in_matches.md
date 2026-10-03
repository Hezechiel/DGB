# Claude Code prompt — Scrolls step 3: levels and synergy in matches

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 2 is merged (`scripts/PlayerProfile.gd` exists, `MatchConfig` has `local_deck_card_ids`). If not, stop and tell me.

## Goal

Card and god levels from the player's profile change stats in a match, and the god's domain synergy applies to matching units. Spawn messages stay `{card_id, position, team}` — the level is **never** passed per spawn. Instead a per-team **match manifest** (god id, god level, card levels) is set once at match start and looked up by team.

What scales (multipliers come from `data/progression/level_curve.tres`):

| Thing | Level scales | Synergy can scale |
|---|---|---|
| Unit | max HP, damage | max HP, damage, move speed, attack speed |
| Spell | damage only | nothing |
| God | max HP, damage, attack speed | nothing (synergy is for units) |

Never scaled: stun/root/slow durations, spell radius, cast time, zone duration, card cost, ranges.

**Attack speed, simple version (deliberate, a rework is planned later):** a multiplier `m` only shortens the post-hit timer — unit `attack_cooldown / m`, god `recovery_time / m`. Do not touch animation speed, `speed_scale`, windup or cast-point code.

Shared resources are never written to: every scaled value lives on the spawned node. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. `scripts/MatchConfig.gd` — add levels to the manifest fields

Below the four existing deck fields:

```gdscript
# Levely pre zapas (manifest). card_levels: StringName card_id -> int level.
var local_hero_level: int = 1
var local_card_levels: Dictionary = {}
var opponent_hero_level: int = 1
var opponent_card_levels: Dictionary = {}
```

Update the comment above the deck fields: remove "levely pridu v dalsom kroku".

## 2. `scripts/ui/prematch_flow.gd` — fill them

Directly after the four existing `MatchConfig.*` deck assignments in `_ready()`:

```gdscript
	# Levely z profilu; AI zrkadli aj levely (rozhodnutie #10 — ferovy zaklad).
	MatchConfig.local_hero_level = PlayerProfile.get_hero_level(MatchConfig.local_hero_id)
	var levels: Dictionary = {}
	for id in MatchConfig.local_deck_card_ids:
		levels[id] = PlayerProfile.get_card_level(id)
	MatchConfig.local_card_levels = levels
	MatchConfig.opponent_hero_level = MatchConfig.local_hero_level
	MatchConfig.opponent_card_levels = levels.duplicate()
```

## 3. `scripts/BattleManager.gd` — manifest + multiplier lookup

Add (near the other per-match state):

```gdscript
const LEVEL_CURVE: LevelCurve = preload("res://data/progression/level_curve.tres")

# Match manifest: team -> {"hero_id": StringName, "hero_level": int,
# "card_levels": Dictionary}. Nastavuje arena.gd raz na zaciatku zapasu
# (neskor pride zo siete). Spawn spravy ostavaju {card_id, pos, team} —
# level sa NIKDY neposiela per spawn, vzdy sa dohlada tu podla timu.
var _manifests: Dictionary = {}

func set_team_manifest(team: String, hero_id: StringName, hero_level: int, card_levels: Dictionary) -> void:
	_manifests[team] = {
		"hero_id": hero_id,
		"hero_level": maxi(1, hero_level),
		"card_levels": card_levels.duplicate(),
	}

func get_card_level(team: String, card_id: StringName) -> int:
	# Chybajuci manifest/karta = level 1 (nikdy nezhodi zapas).
	if not _manifests.has(team):
		return 1
	return maxi(1, int(_manifests[team]["card_levels"].get(card_id, 1)))

func get_hero_level(team: String) -> int:
	if not _manifests.has(team):
		return 1
	return _manifests[team]["hero_level"]
```

- `reset_match_state()`: also clear `_manifests` (`_manifests = {}`), next to the other per-match registries.

Two private helpers that build the multiplier dictionaries. Keys are always these four `StringName`s, each defaulting to `1.0`: `&"max_hp"`, `&"damage"`, `&"speed"`, `&"attack_speed"`.

```gdscript
# Nasobice pre jednotku z karty: level (HP + damage) x synergy boha timu.
# Synergy plati len ked karta MA domain a zhoduje sa s domain boha timu.
# &"" domain = common pool = ziadna synergy.
func _unit_stat_mods(card: CardData, team: String) -> Dictionary:
	var level_mult := LEVEL_CURVE.get_stat_multiplier(get_card_level(team, card.id))
	var mods := {&"max_hp": level_mult, &"damage": level_mult, &"speed": 1.0, &"attack_speed": 1.0}
	if card.domain == &"" or not _manifests.has(team):
		return mods
	var hero_id: StringName = _manifests[team]["hero_id"]
	if not CardDB.has_hero(hero_id):
		return mods
	var hero_data := CardDB.get_hero(hero_id)
	if hero_data.domain != card.domain:
		return mods
	for stat in mods.keys():
		mods[stat] *= float(hero_data.synergy_bonuses.get(stat, 1.0))
	return mods

# Nasobice pre boha: level skaluje HP, damage a (mensim stropom) attack speed.
func _hero_stat_mods(team: String) -> Dictionary:
	var level := get_hero_level(team)
	var m := LEVEL_CURVE.get_stat_multiplier(level)
	return {&"max_hp": m, &"damage": m, &"speed": 1.0,
		&"attack_speed": LEVEL_CURVE.get_hero_attack_speed_multiplier(level)}
```

Use them at the three existing entry points (change only these call lines, plus one debug print each):

- `spawn_unit()`: compute `var mods := _unit_stat_mods(card, team)` **once before the squad loop**, then `unit.configure(unit_data, team, mods)`. After the loop: `print("[spawn] %s team=%s L%d mods=%s" % [card_id, team, get_card_level(team, card_id), mods])`.
- `cast_spell()`: `zone.configure(card.spell_data, team, pos, LEVEL_CURVE.get_stat_multiplier(get_card_level(team, card_id)))`.
- `spawn_hero()`: `hero.configure(data, team, _hero_stat_mods(team))`, and `print("[spawn] %s team=%s L%d mods=%s" % [hero_id, team, get_hero_level(team), ...])`.

## 4. `scripts/arena/arena.gd` — set the manifests

In `_ready()`, **before** the first `BattleManager.spawn_hero(...)` call (the gods read their level from the manifest):

```gdscript
	# Match manifest — raz na zaciatku, pred spawnom hrdinov (levely bohov).
	BattleManager.set_team_manifest("player", MatchConfig.local_hero_id,
		MatchConfig.local_hero_level, MatchConfig.local_card_levels)
	BattleManager.set_team_manifest("enemy", MatchConfig.opponent_hero_id,
		MatchConfig.opponent_hero_level, MatchConfig.opponent_card_levels)
```

Nothing else in `arena.gd` changes.

## 5. `scripts/arena/unit.gd` — `configure()` (lines 122–136)

New signature `func configure(data: UnitData, new_team: String, stat_mods: Dictionary = {}) -> void:`. Replace the four plain copies:

```gdscript
	# stat_mods = nasobice z BattleManager (level + synergy). Skalovane
	# hodnoty ziju LEN na tomto uzle — UnitData resource sa nikdy nemeni.
	max_hp = roundi(data.max_hp * float(stat_mods.get(&"max_hp", 1.0)))
	damage = roundi(data.damage * float(stat_mods.get(&"damage", 1.0)))
	# attack speed = zatial len kratsi cooldown po zasahu (rework neskor)
	attack_cooldown = data.attack_cooldown / maxf(float(stat_mods.get(&"attack_speed", 1.0)), 0.01)
	speed = data.speed * float(stat_mods.get(&"speed", 1.0))
```

Every other line of `configure()` stays as it is.

## 6. `scripts/arena/player.gd` (lines 81–97) and `scripts/arena/hero_dummy.gd` (lines 86–100) — `configure()`

Both get the same third parameter `stat_mods: Dictionary = {}` and the same three changes:

```gdscript
	max_hp = roundi(data.max_hp * float(stat_mods.get(&"max_hp", 1.0)))
	projectile_damage = roundi(data.projectile_damage * float(stat_mods.get(&"damage", 1.0)))
	# attack speed = zatial len kratsi recovery po zasahu (rework neskor)
	recovery_time = data.recovery_time / maxf(float(stat_mods.get(&"attack_speed", 1.0)), 0.01)
```

`speed` is not scaled for gods. Every other line stays.

## 7. `scripts/arena/spell_zone.gd`

- `configure(data: SpellData, team: String, pos: Vector2, damage_mult: float = 1.0)` — store `_damage = roundi(data.damage * damage_mult)` in a new `var _damage: int = 0` (declare it with the other state vars).
- Line 124: `n.take_damage(spell.damage)` → `n.take_damage(_damage)`.
- Nothing else: durations, radius, slow and animation code are untouched.

## DO NOT TOUCH

- `scripts/PlayerProfile.gd`, `scripts/CardDB.gd`, `scripts/level_curve.gd`, `scripts/EnergySystem.gd`, `scripts/HealingSystem.gd`, `scripts/HeroAI.gd`.
- `scripts/arena/ui/card_hand.gd`, `scripts/arena/enemy_card_ai.gd` (they keep sending only `card_id`, position, team).
- `scripts/arena/turret.gd`, `scripts/arena/base.gd` (structure scaling is a later feature).
- In `unit.gd` / `player.gd` / `hero_dummy.gd`: anything outside `configure()` — windup, cast-point, cooldown ticking, animation, status effects, respawn.
- Everything under `data/`, `assets/`, all `.tscn`, `project.godot`.
- `docs/`, `CLAUDE.md`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- `upgrade_card()`, granting cards, any profile change, any UI showing levels.
- The god's passive-ability condition that will later gate synergy — synergy is always on for matching domains in this step.
- Attack-speed rework (animation / windup scaling).
- Scaling of turrets, bases, healing pods, energy, costs.
- Setting `domain` on any card `.tres`.
- Sending levels over a network, validating manifests against an inventory.
- Removing the debug prints (they stay until the debug panel step).

## VERIFY

Static checks (run and report output):

1. `grep -rn "\.configure(" scripts/BattleManager.gd` — three calls, each passing the new extra argument.
2. `grep -n "func configure" scripts/arena/unit.gd scripts/arena/player.gd scripts/arena/hero_dummy.gd scripts/arena/spell_zone.gd` — four signatures, each with a defaulted last parameter.
3. `grep -n "spell.damage" scripts/arena/spell_zone.gd` — no match.
4. `grep -rn "_manifests" scripts/` — only `BattleManager.gd`, including one line inside `reset_match_state()`.
5. `grep -rn "level" scripts/arena/ui/card_hand.gd scripts/arena/enemy_card_ai.gd` — no new level handling in either file.
6. `grep -rn "data\.max_hp = \|data\.damage = \|unit_data\.\w* = \|hero_data\.\w* = \|spell\.\w* = " scripts/arena/` — no assignment into a shared resource.
7. `git status --short` — only the seven files named in sections 1–7.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. With an untouched profile (everything level 1): a match plays exactly as before; every `[spawn]` line shows `L1` and all four mods `1.0`.
2. Edit `profile.json`: set `card_greek_hoplite` level to `10` and `hero_zeus` level to `10`. Relaunch and start a match. Hoplite `[spawn]` line shows `L10` with `max_hp` and `damage` `1.48`; its health bar holds 222 HP (150 × 1.48). Zeus shows `max_hp`/`damage` `1.48`, `attack_speed` `1.18`.
3. In the same match the enemy's Hoplites and Poseidon show the same levels (AI mirrors).
4. Set `card_greek_storm` to level 10: Storm ticks deal 22 instead of 15; its slow and duration are unchanged; Stun at level 10 stuns for the same time as at level 1.
5. Synergy: temporarily set `domain = olympus` on `card_greek_hoplite.tres` in the Inspector. Player Hoplites (Zeus, Olympus) show mods multiplied by 1.1; enemy Hoplites (Poseidon, Sea) do not. Revert the card afterwards.
6. Restore `profile.json` levels to 1 (or delete the file) when done.
