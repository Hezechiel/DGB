# Claude Code prompt — Structure-destroyed sounds + base-destroyed end sequence (camera + delay before MatchEndScreen)

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Two new assets exist:
- `res://assets/audio/sfx/combat/structures/turret_destroyed_01.wav` (2.7 s)
- `res://assets/audio/sfx/combat/structures/base_destroyed_01.wav` (3.5 s)

**Turrets:** `turret.gd` already calls `AudioManager.play_sfx(destroyed_sfx, global_position)` in `_on_destroyed()`. But `data/sounds/turret_destroyed.tres` has an empty `streams` array, so it's silent and warns once. The fix is data only.

**Base:** today, `base.gd::_on_destroyed()` → `BattleManager.on_base_destroyed()` → `match_ended` → `arena.gd::_on_match_ended()` → `change_scene_to_file(MatchEndScreen)`, all in the same frame. Nothing played on the arena gets heard, and the player never sees the base fall.

This step adds a short **end sequence**, the way other MOBAs do it: the camera pans and zooms onto the destroyed base, the collapse sound plays, input and the HUD are disabled, and after about 3.5 s the game changes to `MatchEndScreen` (which then plays its victory/defeat stinger, as it already does).

**Design rule:** the match *result* stays logic and is decided instantly. `BattleManager` still emits `match_ended` in the same frame; nothing in `BattleManager`'s decision flow waits. The delay, camera and sound are **presentation only**, owned by `arena.gd`, `ArenaCamera` and `base.gd`. A future server would decide the winner at the same moment, and each client would play its own end sequence.

## Files to read first

- `scripts/BattleManager.gd` (`on_base_destroyed()`, `_match_ended`, the match timer's draw branch, `player_base` / `enemy_base`)
- `scripts/arena/base.gd` (`_on_destroyed()`)
- `scripts/arena/turret.gd`: read only (`destroyed_sfx` export, `_on_destroyed()`); it's the pattern to mirror
- `scripts/arena/arena.gd` (`_on_match_ended()`, `_unhandled_input()`, `_on_deploy_preview_ended()`, `_exit_tree()`)
- `scripts/arena/arena_camera.gd` (whole file: `_physics_process()`, `_unhandled_input()`, `_clamp_point()`, `recenter_on_player()` / `_recenter_tween`)
- `scripts/arena/ui/card_hand.gd` (`play_card()`)
- `scripts/arena/enemy_card_ai.gd`: read only (already gated on `EnergySystem.is_running()`)
- `scripts/hud/HUD.gd`: read only (a `CanvasLayer`, reached from `arena.gd` as `hud`)
- `scripts/AudioManager.gd`: read only (`play_sfx`, `stop_music`, `stop_announcer`)
- `data/sounds/turret_destroyed.tres`, `data/sounds/zeus_bolt.tres` (format reference)

## Changes

### 1. Data: `data/sounds/turret_destroyed.tres` and NEW `data/sounds/base_destroyed.tres`

- **`turret_destroyed.tres`:** set `streams` to `[res://assets/audio/sfx/combat/structures/turret_destroyed_01.wav]`. Don't change any of its other fields (it stays positional and CRITICAL).
- **NEW `base_destroyed.tres`** (same format as the others):

| id | streams | bus | priority | volume_db | volume_jitter_db | pitch_jitter | max_instances | min_interval | positional |
|---|---|---|---|---|---|---|---|---|---|
| `base_destroyed` | `sfx/combat/structures/base_destroyed_01.wav` | Combat | CRITICAL | 0 | 0.0 | 0.0 | 1 | 0.0 | **false** |

It's **non-positional** on purpose. When the base falls, the camera may still be far away, and a positional sound past `max_distance` would be skipped before the camera even starts moving.

### 2. `scripts/arena/base.gd`: play the collapse sound

- Add `@export var destroyed_sfx: StringName = &"base_destroyed"` next to the other exports. It's a script default, so no `.tscn` edits.
- In `_on_destroyed()`, as the **first** line: `AudioManager.play_sfx(destroyed_sfx)`, with no position. Add a comment: it has to play before `BattleManager.on_base_destroyed()`, which starts the end of the match.

### 3. `scripts/BattleManager.gd`: one read-only getter

```gdscript
# Je zapas rozhodnuty? (base padla / cas vyprsal). Citaju UI/vstup, aby pocas
# zaverecnej sekvencie nic nespawnovali — BattleManager sam nic neoneskoruje.
func is_match_over() -> bool:
	return _match_ended
```

**No other change to `BattleManager.gd`.** In particular, `on_base_destroyed()` and the timer's draw path stay exactly as they are, and no `AudioManager` calls may be added here.

### 4. `scripts/arena/arena_camera.gd`: cinematic mode

Add:

```gdscript
# Zaverecna sekvencia (znicena baza): kamera ide na ciel, hrac ju nemoze
# ovladat, follow/edge-pan/drag su vypnute az do zmeny sceny.
var _cinematic := false

func play_focus(target: Vector2, zoom_mult: float = 1.35, duration: float = 0.8) -> void:
	_cinematic = true
	_is_dragging = false
	_touch_id = -1
	_is_deploy_dragging = false
	if _recenter_tween != null and _recenter_tween.is_valid():
		_recenter_tween.kill()
	var target_zoom := zoom * zoom_mult
	# clamp pocita s CIELOVYM zoomom — pri vacsom zoome je vidiet menej mapy
	var old_zoom := zoom
	zoom = target_zoom
	var target_pos := _clamp_point(target)
	zoom = old_zoom
	var t := create_tween().set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	t.tween_property(self, "position", target_pos, duration)
	t.tween_property(self, "zoom", target_zoom, duration)
```

- At the very top of `_physics_process()`: `if _cinematic: return`.
- At the very top of `_unhandled_input()`: `if _cinematic: return`.

Nothing else in this file changes.

### 5. `scripts/arena/arena.gd`: the end sequence

Add a constant and a flag:

```gdscript
# Dlzka zaverecnej sekvencie po padnuti zakladne — zhruba dlzka base_destroyed zvuku.
const END_SEQUENCE_SECONDS := 3.5
var _match_over := false
```

Replace `_on_match_ended()`:

```gdscript
func _on_match_ended(winner: String) -> void:
	_match_over = true
	EnergySystem.stop()
	if winner == "draw":
		# ziadna budova nepadla — nie je co ukazat, rovno na vysledok
		get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")
		return
	_play_end_sequence(winner)

# Presentation-only: BattleManager uz vysledok rozhodol, tu ho len "ukazeme".
func _play_end_sequence(winner: String) -> void:
	# znicena je zakladna PORAZENEHO timu
	var fallen: Node2D = BattleManager.enemy_base if winner == "player" else BattleManager.player_base
	_on_deploy_preview_ended()          # zrus pripadny rozbehnuty drag karty (ghost, edge-pan)
	hud.visible = false                 # karty, pauza, timer — nic uz nejde stlacit
	AudioManager.stop_announcer()
	AudioManager.stop_music(1.0)        # nech je rucanie zakladne pocut; stinger pride na MatchEndScreen
	if fallen != null and is_instance_valid(fallen):
		arena_camera.play_focus(fallen.global_position)
	await get_tree().create_timer(END_SEQUENCE_SECONDS).timeout
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")
```

At the top of `_unhandled_input()` add `if _match_over: return`, so tap-to-move is locked during the sequence.

Leave the debug `_input()` keys as they are.

### 6. `scripts/arena/ui/card_hand.gd`: gate card plays

In `play_card()`, directly after the existing `is_hero_dead` gate, add `if BattleManager.is_match_over(): return false`. This covers a drag released during the sequence and any future double-tap or network path. `enemy_card_ai.gd` needs no change, because it already stops when `EnergySystem` stops.

## DO NOT TOUCH

- `BattleManager.gd` beyond the one getter: no delay, no `AudioManager` calls, no change to `on_base_destroyed()` or the timer
- `turret.gd`: it already plays `destroyed_sfx`
- `match_end_screen.gd` and the stingers: it keeps playing `stinger_victory` / `stinger_defeat` + menu music on its own
- `AudioManager.gd`, `sound_data.gd`, every other `SoundData` file
- Hero/unit scripts: units and heroes keep acting during the 3.5 s. The result is already decided.
- `.import` files and assets

## Explicitly OUT of scope (flag in the plan if you think one is needed)

- Slow motion (`Engine.time_scale`). It affects every timer and tween and needs careful resetting, so it's a separate step.
- A "VICTORY/DEFEAT" banner over the arena during the sequence (MatchEndScreen shows it)
- Screen shake, a flash or particle effects on the base
- Making heroes/units invulnerable during the sequence. If the player's hero dies in those 3.5 s, the desaturate overlay may kick in; that's accepted for now, but note it if you see it.
- A camera sequence for turret destruction (sound only)
- An end sequence for a draw

## VERIFY

Static checks:
- `grep -n "is_match_over" scripts/` → the definition in `BattleManager.gd`, plus uses in `card_hand.gd` only.
- `grep -n "AudioManager" scripts/BattleManager.gd` → no results.
- `grep -n "destroyed_sfx" scripts/arena/base.gd scripts/arena/turret.gd` → one export + one `play_sfx` call in each.
- `ls data/sounds/` → the previous files + `base_destroyed.tres`. `turret_destroyed.tres` has one stream.
- `git diff --stat` shows only `base.gd`, `BattleManager.gd`, `arena.gd`, `arena_camera.gd`, `card_hand.gd`, `turret_destroyed.tres` and the new `base_destroyed.tres`.

Runtime tests:
1. **Turret:** destroy an enemy turret, and one of your own (let the AI take it). The rubble sound plays from the turret's side of the screen, and there's no `chyba asset` warning any more.
2. **Victory:** destroy the enemy base.
   - The collapse sound starts immediately, even if the camera was far away.
   - Battle music fades out.
   - The camera smoothly pans and zooms (about 0.8 s) onto the base, correctly clamped even though the base sits near the map edge (no empty space past the border).
   - The HUD disappears.
   - About 3.5 s after the base fell, `MatchEndScreen` shows and the victory stinger plays.
3. **Defeat:** let the AI destroy your base → the same sequence on your base, then the defeat stinger.
4. **Input lock during the sequence:** tapping the map doesn't move the hero, dragging doesn't pan the camera, there's no pause button. If you were dragging a card at the moment the base fell, the ghost disappears and releasing spawns nothing.
5. **Lock-camera mode** (Settings) → the camera still goes to the base and doesn't snap back to the hero.
6. **Draw** (let the timer run out) → `MatchEndScreen` immediately, as before.
7. **No double end:** no second `match_ended` and no errors in the console; the next match (menu → Battle) starts normally with the HUD visible, the camera controllable, and cards playable.
8. Announcer: if "first blood" was still playing at the moment the base fell, it stops.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
