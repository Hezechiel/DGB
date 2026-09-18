# Claude Code Prompt — MatchInfoBar tower icons: grey out on turret destruction

**Enter Plan Mode first.** Present the full diff for review before touching any files.

## Context

`scenes/arena/ui/MatchInfoBar.tscn` has 3 tower-icon `Panel` nodes per side
(`PlayerTowers/Tower1,2,3` and `EnemyTowers/Tower1,2,3`), currently static placeholder color
blocks (`StyleBoxFlat_towerBlue` / `StyleBoxFlat_towerRed`, each shared across all 3 Tower
panels on that side). `scripts/arena/ui/match_info_bar.gd`'s own top comment already lists this
as planned but unwired: "ikony znicenych veze (PlayerTowers / EnemyTowers)".

Goal: grey out each tower icon when its corresponding turret is destroyed — same visual
treatment already used on the minimap (`scripts/arena/ui/minimap.gd`'s `COLOR_DESTROYED`,
applied via the turret's existing `signal destroyed`, `scripts/arena/turret.gd`).

### Important finding — Tower1/2/3 must NOT be mapped by `get_turrets()` array index

`BattleManager.get_turrets(team)` (already exists, added for the minimap) returns
`top`-lane turrets followed by `bot`-lane turrets, each bucket in scene-registration order.
Checked directly against both existing map scenes
(`scenes/arena/maps/GreekPlateauMap.tscn`, `scenes/arena/maps/NordPlainsMap.tscn`):

- Player side turret children: `PlayerTurretBase` (lane "bot"), `PlayerTurretTop` (lane "top",
  default), `PlayerTurretBot` (lane "bot") → `get_turrets("player")` order is
  `[Top, Base, Bot]`.
- Enemy side turret children: `EnemyTurretTop` (lane "top"), `EnemyTurretBot` (lane "bot"),
  `EnemyTurretBase` (lane "bot") → `get_turrets("enemy")` order is `[Top, Bot, Base]`.

**These two orders are different from each other** on both current maps. A naive
`get_turrets(team)[i] → TowerN` mapping would show the wrong lane's icon going grey on the
enemy side (and isn't guaranteed to stay consistent on future maps either, since nothing
enforces a fixed child-registration order).

Fix: resolve each turret's icon slot from its **node name** (`"Top"`/`"Base"`/`"Bot"`
substring), the same pattern already established in this codebase for `HealingPod`
(`owning_side` is derived from node name at runtime, not scene order or an exported field —
see `architecture.md`). This requires zero changes to `BattleManager.gd` or `turret.gd` —
`get_turrets()` already exists and `destroyed` already fires once per turret.

Slot assignment for this prompt: `Tower1 = Top lane`, `Tower2 = Base lane` (the base-adjacent
turret), `Tower3 = Bot lane`. This is a UI-only convention (left-to-right = top-to-bottom lane
order); flag if you'd rather have a different assignment.

### Timing — must be wired from `arena.gd`, not from `MatchInfoBar._ready()`

`HUD` (and its child `MatchInfoBar`) already exists in `arena.tscn` at scene load, so
`MatchInfoBar._ready()` runs **before** `arena.gd`'s own `_ready()` body executes — before the
map scene is instantiated and before any turret has self-registered with `BattleManager`. Same
class of ordering bug already hit and fixed once for the minimap's hero icons (see
`arena.gd`'s comment above `map_root.add_child(map_instance)` / the `hud.minimap.configure_map()`
call). Fix: expose a public `wire_tower_icons()` method on `MatchInfoBar` and call it explicitly
from `arena.gd`, right after `BattleManager.configure_map(map_data)` — turret registration is
synchronous and complete by then (doesn't need to wait for heroes, unlike the minimap).

## Files to inspect first (Plan Mode — read before editing)

- `scenes/arena/ui/MatchInfoBar.tscn`
- `scripts/arena/ui/match_info_bar.gd`
- `scripts/arena/arena.gd`
- `scripts/BattleManager.gd` (read-only — confirm `get_turrets(team)` still matches what's
  described above; do not modify)
- `scripts/arena/turret.gd` (read-only — confirm `signal destroyed` still fires once from
  `_on_destroyed()`; do not modify)

Confirm current content matches what's described before applying — if the live files differ
(especially map scene turret names/lanes, or if `get_turrets()`'s signature changed), stop and
flag the mismatch instead of guessing.

## Changes

### 1. `scripts/arena/ui/match_info_bar.gd`

Add the wiring logic. Insert after the existing `@onready var enemy_respawn_counter` line:

```gdscript
func _ready() -> void:
	BattleManager.hero_died.connect(_on_hero_died)
	BattleManager.hero_respawn_tick.connect(_on_hero_respawn_tick)
	BattleManager.hero_respawned.connect(_on_hero_respawned)
	BattleManager.match_time_tick.connect(_on_match_time_tick)

# Volane z arena.gd, hned po BattleManager.configure_map() — vtedy uz su vsetky
# struktury (turrety) zaregistrovane (self-register vo vlastnom _ready(), ktore
# bezi PRED _ready() rodica, teda uz pred timto bodom). MatchInfoBar._ready() sa
# na to spolahnut NEMOZE — HUD je uz v arena.tscn od zaciatku, takze jeho _ready()
# bezi PRED _ready() arena.gd (teda PRED instanciovanim mapy) — rovnaky dovod ako
# presun Minimap.configure_map() volania v arena.gd.
func wire_tower_icons() -> void:
	_wire_team_towers("player", player_towers)
	_wire_team_towers("enemy", enemy_towers)

# Tower1/2/3 su fixne UI sloty (vizualne poradie v bare), NIE index do
# BattleManager.get_turrets() — to pole je zoradene podla lane-bucketu (top
# potom bot) a poradie v ramci "bot" bucketu zavisi od poradia registracie v
# map scene, ktore sa REALNE LISI medzi player a enemy stranou na existujucich
# mapach (over v GreekPlateauMap.tscn / NordPlainsMap.tscn). Identita slotu preto
# ide cez meno node-u ("Top"/"Base"/"Bot" substring) — rovnaky princip ako
# HealingPod.owning_side (architecture.md) — nie cez poziciu v poli.
func _wire_team_towers(team: String, towers_container: HBoxContainer) -> void:
	var slot_icons := {
		"Top": towers_container.get_node("Tower1") as Panel,
		"Base": towers_container.get_node("Tower2") as Panel,
		"Bot": towers_container.get_node("Tower3") as Panel,
	}
	for turret in BattleManager.get_turrets(team):
		for slot_name in slot_icons.keys():
			if slot_name in turret.name:
				var icon: Panel = slot_icons[slot_name]
				turret.destroyed.connect(_on_tower_destroyed.bind(icon), CONNECT_ONE_SHOT)
				break

# Tower1/2/3 v ramci jedneho timu zdielaju JEDEN StyleBoxFlat sub_resource
# (StyleBoxFlat_towerBlue / _towerRed) — priamo prepisat jeho bg_color by
# zosedivelo VSETKY veze naraz. Preto duplicate() + per-Panel override, rovnaky
# princip ktory uz raz sposobil problem pri Card cost labeli (zdielany
# StyleBoxEmpty_cost).
func _on_tower_destroyed(icon: Panel) -> void:
	var style: StyleBoxFlat = (icon.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	style.bg_color = Minimap.COLOR_DESTROYED  # rovnaky odtien ako minimapa — vizualna konzistencia
	icon.add_theme_stylebox_override("panel", style)
```

Leave `_on_hero_died`, `_on_hero_respawn_tick`, `_on_hero_respawned`, `_counter_for`,
`_on_match_time_tick` untouched.

### 2. `scripts/arena/arena.gd`

In `_ready()`, add the call right after `arena_camera.configure_map(map_data)`:

```gdscript
	BattleManager.configure_map(map_data)
	arena_camera.configure_map(map_data)
	hud.match_info_bar.wire_tower_icons()
```

Leave everything else in `_ready()` (and the rest of the file) untouched.

## DO NOT TOUCH

- `scripts/BattleManager.gd` — `get_turrets()` already exists and is sufficient; no changes.
- `scripts/arena/turret.gd` — `signal destroyed` already fires correctly; no changes.
- `scripts/arena/base.gd` — bases are not part of the tower-icon row (only the 3 turrets per
  side are); no changes.
- `scripts/arena/ui/minimap.gd`, `scenes/arena/ui/Minimap.tscn` — read-only reference for
  `COLOR_DESTROYED`; no changes.
- `scenes/arena/maps/GreekPlateauMap.tscn`, `scenes/arena/maps/NordPlainsMap.tscn` — no changes;
  the node-name-based slot lookup works with their current turret names as-is.
- `scenes/arena/ui/MatchInfoBar.tscn` — no scene changes needed at all; the greying is done
  entirely via a per-Panel theme override in code, not by editing the scene's StyleBoxFlat
  sub-resources.
- `_on_hero_died`, `_on_hero_respawn_tick`, `_on_hero_respawned`, `_on_match_time_tick`,
  `_counter_for` in `match_info_bar.gd`.
- Any other HUD child (`CardHand`, `EnergyBar`, `PauseButton`, `PlayerCharacter`,
  `DeathTelegraph`, `SettingOverlay`).

## Out of scope

- Do NOT add any fade/animation to the greying (instant recolor only, matching the minimap's
  instant recolor on `destroyed`).
- Do NOT try to handle a map with a different turret count/naming scheme than the current
  `Top`/`Base`/`Bot` convention — both existing maps follow it; a future map that doesn't would
  need a separate look.
- Do NOT resurrect or touch base-destruction visuals — out of scope, bases aren't represented
  in this row.

## VERIFY

1. `grep -n "wire_tower_icons\|_wire_team_towers\|_on_tower_destroyed" scripts/arena/ui/match_info_bar.gd`
   — confirm all three functions are present.
2. `grep -n "wire_tower_icons" scripts/arena/arena.gd` — confirm the call is present, placed
   right after `arena_camera.configure_map(map_data)`.
3. Run a match: confirm all 6 tower icons (3 blue, 3 red) render at their original colors at
   match start — no visual change until a turret dies.
4. Destroy one player-side turret (e.g. via the `KEY_H` debug damage hook on `arena.gd`, or
   in-game combat) and confirm the correct single icon greys out — specifically verify a
   **Bot-lane** turret's destruction greys `Tower3` (not `Tower1`/`Tower2`), since that's the
   case most likely to catch an index-vs-name mixup.
5. Destroy an **enemy-side** turret and confirm the correct icon greys out there too — this is
   the critical check given the confirmed order mismatch between player/enemy `get_turrets()`
   results.
6. Confirm destroying one turret does NOT grey out the other 2 icons on the same side (the
   shared-StyleBoxFlat regression check).
7. Confirm turrets that are NOT destroyed keep their original blue/red color throughout the
   match, and that the minimap's own turret dots (from the earlier minimap work) are unaffected
   by this change.
