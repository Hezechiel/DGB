# Claude Code prompt — Audio phase 3a: map ambient (bed loop + random one-shot emitters)

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Phases 1 and 2 are done. `AudioManager` owns music, UI, voice, the positional SFX pool (`play_sfx(id, pos)`) and the `SoundData` registry (`data/sounds/*.tres`). The `Environment` bus (under `SFX`) exists but nothing uses it yet.

This step adds map ambient sound, using the standard two layers:
- **Bed:** one continuous quiet loop (e.g. Norse ice). It plays all the time on its own `AudioStreamPlayer`, never through the SFX pool. A looping sound would hold a pool voice forever, and if priority stealing took it, the bed would go silent for the rest of the match.
- **One-shots:** short sounds at **random intervals** (Greek harp phrases, cymbals), played through `AudioManager.play_sfx()` so the pool, priorities and jitter all apply.

Both come from a new **`AmbientEmitter`** node that is **hand-placed in each map scene**, the same way turrets and healing pods are. It lives with the map scene, so match end and scene change clean it up automatically, with no reset code. This follows the architecture.md rule "timed effects belong on a scene node, not in an autoload".

## Files to read first

- `scripts/AudioManager.gd` (`play_sfx()`, `_warn_once()`, `_sounds`)
- `scripts/sound_data.gd`
- `data/sounds/sword_hit.tres`: read only; it's the format reference for new `SoundData` files
- `scenes/arena/maps/GreekPlateauMap.tscn`, `scenes/arena/maps/NordPlainsMap.tscn` (root node, existing children)
- `scenes/arena/maps/HealingPod.tscn` + `scripts/arena/healing_pod.gd`: read only; the pattern for a small reusable node placed in map scenes
- `assets/audio/ambient/**/*.import`: read only; check the `loop=` flags (see the note at the end of step 4)

## Changes

### 1. `scripts/AudioManager.gd`: one public helper

Add, in the SFX section:

```gdscript
# Verejny lookup SoundData pre nody, ktore si prehravaju zvuk samy (ambient bed).
# Neznáme id = raz varuje a vrati null; prazdne id = ticho, null bez varovania.
func get_sound(id: StringName) -> SoundData:
	if id == &"":
		return null
	var def: SoundData = _sounds.get(id)
	if def == null:
		_warn_once(id, "neznamy sound id")
	return def
```

Update the header comment line: phase 3a = ambient (`AmbientEmitter`, on the map scene, not in the manager). **No other changes to `AudioManager.gd`.**

### 2. NEW `scripts/arena/ambient_emitter.gd` + `scenes/arena/audio/AmbientEmitter.tscn`

The scene is a single `Node2D` root named `AmbientEmitter` with this script. No children in the scene: the bed player is created in code only in LOOP mode.

```gdscript
extends Node2D
class_name AmbientEmitter

# Ambient zvuk mapy — umiestneny RUCNE v scene mapy (pod uzlom "Ambient"),
# rovnako ako veze/pody. Zije so scenou mapy: koniec zapasu / zmena sceny ho
# uprace bez akehokolvek reset kodu. Pauzuje sa spolu s hrou (dedi process_mode).
#   LOOP   = podklad (bed) — vlastny AudioStreamPlayer, hra stale, NIE cez SFX pool
#            (loop by navzdy blokoval hlas v poole a steal by ho umlcal).
#   RANDOM = one-shot cez AudioManager.play_sfx() v nahodnych intervaloch.
# Pozicia uzla sa pouzije len ak SoundData.positional = true.

enum Mode { LOOP, RANDOM }

@export var sound_id: StringName
@export var mode: Mode = Mode.RANDOM
# RANDOM: dalsi one-shot o nahodny cas z <min, max> sekund.
@export var min_interval: float = 15.0
@export var max_interval: float = 35.0
# RANDOM: prvy one-shot az po nahodnom oneskoreni — nie hned pri nacitani mapy.
@export var first_delay_min: float = 5.0
@export var first_delay_max: float = 15.0
# LOOP: nabeh hlasitosti podkladu pri starte zapasu.
@export var loop_fade_in: float = 2.0

var _left: float = 0.0
var _bed: AudioStreamPlayer = null

func _ready() -> void:
	if mode == Mode.LOOP:
		set_process(false)
		_start_bed()
	else:
		_left = randf_range(first_delay_min, first_delay_max)

func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = randf_range(min_interval, max_interval)
	AudioManager.play_sfx(sound_id, global_position)

func _start_bed() -> void:
	var def := AudioManager.get_sound(sound_id)
	if def == null or def.streams.is_empty():
		return  # get_sound uz varoval / asset chyba — mapa ostane bez podkladu
	_bed = AudioStreamPlayer.new()
	_bed.bus = def.bus
	_bed.stream = def.streams.pick_random()
	add_child(_bed)
	_bed.volume_linear = 0.0
	_bed.play()
	create_tween().tween_property(_bed, "volume_linear", db_to_linear(def.volume_db), loop_fade_in)
```

Plan checks:
- Confirm the bed actually loops. That depends on the OGG's import `loop=true`, not on code. If the plan finds that a non-looping stream can reach LOOP mode unnoticed, add a single `push_warning` for that case and nothing more.
- Confirm that `_process` and the bed stop while the tree is paused (the map scene is under `Arena`, which inherits the pausable mode).

### 3. NEW `data/sounds/` ambient `SoundData`

Same file format as `sword_hit.tres`. Every path is under `res://assets/audio/ambient/`.

| file / id | streams | bus | priority | volume_db | volume_jitter_db | pitch_jitter | max_instances | min_interval | positional |
|---|---|---|---|---|---|---|---|---|---|
| `amb_greek_harp` | `greek/amb_greek_harp_01…06.ogg` | Environment | LOW | -10 | 2.0 | **0.0** | 1 | 0.0 | false |
| `amb_greek_cymbals` | `greek/amb_greek_cymbals.ogg` | Environment | LOW | -12 | 2.0 | 0.03 | 1 | 0.0 | false |
| `amb_norse_thin_ice` | `norse/amb_norse_thin_ice.ogg` | Environment | LOW | -14 | 0.0 | 0.0 | 1 | 0.0 | false |

The harp has `pitch_jitter = 0.0` on purpose: harp phrases are tonal, and shifting their pitch would put them out of tune with the battle music.

### 4. Map scenes: place the emitters

In each map scene, add a plain `Node2D` named **`Ambient`** as a direct child of the root (after `EnemyStructures`), then instance `AmbientEmitter.tscn` under it:

**`GreekPlateauMap.tscn`**
- `HarpEmitter`: `sound_id = &"amb_greek_harp"`, `mode = RANDOM`, `min_interval = 15`, `max_interval = 35`, `first_delay_min = 5`, `first_delay_max = 15`
- `CymbalsEmitter`: `sound_id = &"amb_greek_cymbals"`, `mode = RANDOM`, `min_interval = 30`, `max_interval = 60`, `first_delay_min = 20`, `first_delay_max = 40`

**`NordPlainsMap.tscn`**
- `IceBed`: `sound_id = &"amb_norse_thin_ice"`, `mode = LOOP`

Leave every emitter at position `(0, 0)`: all three sounds are non-positional. Every new node needs a `unique_id` that isn't used anywhere else in its file. Don't reorder or touch any existing nodes.

**Note for the plan, not for editing:** `amb_greek_cymbals.ogg.import` currently has `loop=true`. I'll switch it to `false` in the Import dock myself before testing. If you see any other ambient one-shot with `loop=true`, list it in the plan and **don't edit `.import` files**.

## DO NOT TOUCH

- `play_sfx()`, pool, priority and stealing logic, music, UI, voice and volume code in `AudioManager.gd`
- `sound_data.gd`: its `bus` enum already includes `Environment`
- `default_bus_layout.tres`, `settings.gd`, `setting_overlay.tscn`
- `MapData` / `data/maps/*.tres`: ambient setup lives in the map **scene**, not in `MapData`
- `arena.gd`, `BattleManager.gd` and every other autoload
- Existing nodes in both map scenes, and all `.import` files

## Explicitly OUT of scope

- Positional ambient sources (a waterfall or temple that gets louder as the camera approaches). The emitter already supports it through `SoundData.positional`, but no map uses it yet.
- A separate ambient volume slider (the Effects slider covers `Environment`)
- Lowering music volume under ambient, or coordinating emitters so harp and cymbals never overlap
- Day/night or intensity-based ambient layers

## VERIFY

Static checks:
- `grep -rn "AmbientEmitter" scenes/arena/maps/` → 2 instances in `GreekPlateauMap.tscn`, 1 in `NordPlainsMap.tscn`.
- `grep -rn "AudioManager\." scripts/arena/ambient_emitter.gd` → only `get_sound` and `play_sfx`.
- `ls data/sounds/` → the 7 phase 2 files + the 3 new `amb_*` files.
- `git diff --stat` shows only `AudioManager.gd`, the two map scenes, and the new emitter script, scene and 3 `.tres` files.

Runtime tests (after I set cymbals to `loop=false`):
1. **Greek Plateau:** no ambient in the first ~5 s. Then harp phrases come at irregular 15–35 s gaps, never the same phrase twice in a row, and never out of tune with the music. Cymbals come rarely (30–60 s). Nothing loops or piles up.
2. **Nord Plains:** the ice bed fades in over about 2 s at match start and loops without a gap or click at the loop point for a full match.
3. **Pause** (settings overlay) → the bed and the random timers pause, then resume on close. No burst of queued one-shots after unpausing.
4. **Effects slider** → ambient gets quieter with it. Music and Voice sliders don't affect it.
5. **Mixing:** in a big fight on Greek Plateau, combat sounds win. A harp phrase can be dropped when the non-positional pool is full, which is fine; combat sounds must never be cut off by ambient.
6. **Leave the match** (HUD exit and via match end) → the ambient stops immediately, with nothing carrying into the menu. Play 3 matches in a row on each map → no stacked beds, no errors.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
