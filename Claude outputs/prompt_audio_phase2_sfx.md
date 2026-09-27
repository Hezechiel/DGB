# Claude Code prompt — Audio phase 2: positional SFX pool, SoundData, priorities, combat hooks

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Phase 1 is done. `AudioManager` (`scripts/AudioManager.gd`) handles music, UI sounds, voice and volumes, and the bus layout already has `Combat` and `Environment` under `SFX`.

Combat sounds today still go through a per-hero `$AttackSfx` node (`AudioStreamPlayer2D`) fed by `HeroData.attack_sound`. No hero actually sets that field, so the game is silent in combat.

This step adds:
- **`play_sfx(id, pos)`**: a pool of positional `AudioStreamPlayer2D` voices owned by `AudioManager`. Includes per-sound instance limits, a minimum retrigger interval, priority-based voice stealing, and skipping sounds too far from the camera.
- **`SoundData`**: one `.tres` per sound event in `data/sounds/`, scanned at startup (same pattern as `CardDB`). Holds variants (random, never the same one twice in a row), pitch/volume jitter, bus and priority.
- **Combat hooks**: hero and unit attacks, hero and unit deaths, turret destroyed.
- **Removal** of the old `$AttackSfx` nodes and `HeroData.attack_sound`.

The design rule from phase 1 still applies. Audio is presentation only and client-side. `play_sfx()` is called only from scene nodes (heroes, units, turrets), never from `BattleManager`, `EnergySystem`, `HealingSystem` or `HeroAI`. Jitter and variant choice use the global `randf()`/`randi()`, never a seeded gameplay RNG.

## Files to read first

- `scripts/AudioManager.gd`
- `default_bus_layout.tres`: read only
- `scripts/CardDB.gd`: read only; copy its `_scan_into()` pattern, including the `.remap` handling for Android exports
- `scripts/arena/hero_data.gd`, `data/heroes/hero_zeus.tres`, `data/heroes/hero_poseidon.tres`
- `scripts/arena/unit_data.gd`, `data/units/greek_hoplite.tres`, `data/units/greek_toxotes.tres`, `data/units/greek_gastraphetes.tres`
- `scripts/arena/player.gd` (`_perform_attack()`, `update_attack_animation()`, `_play_attack_sound()`, `die()`), `scenes/arena/player.tscn`
- `scripts/arena/hero_dummy.gd` (same functions), `scenes/arena/hero_dummy.tscn`
- `scripts/arena/unit.gd` (`configure()`, `_resolve_attack_hit()`, `die()`)
- `scripts/arena/turret.gd` (`_on_destroyed()`)
- `scripts/arena/arena.gd` (`_input()` debug keys)
- `scripts/arena/arena_camera.gd`: read only; it's the active `Camera2D`, so its screen centre is the 2D audio listener

Also check which audio file paths exist under `assets/audio/sfx/`. The `.tres` files in step 6 reference them.

## Changes

### 1. NEW `scripts/sound_data.gd`: the `SoundData` resource

```gdscript
extends Resource
class_name SoundData

# Definicia jedneho zvukoveho eventu pre AudioManager.play_sfx(id, pos).
# Jeden .tres v data/sounds/ = jeden event (napr. "sword_hit"), nie jeden subor —
# varianty su v `streams`. Resource je ZDIELANY — runtime stav (posledna
# varianta, cas posledneho prehratia) drzi AudioManager, nikdy nie tu.

# Enum je tu (class_name), nie v AudioManageri — enum autoloadu nejde pouzit
# ako typ (architecture.md §6).
enum Priority { LOW, NORMAL, HIGH, CRITICAL }

@export var id: StringName
# Varianty — nahodny vyber, nikdy nie ta ista dvakrat po sebe. Prazdne pole =
# zvuk este nema asset (AudioManager raz varuje a mlci).
@export var streams: Array[AudioStream] = []
@export_enum("Combat", "Environment") var bus: String = "Combat"
@export var priority: Priority = Priority.NORMAL
@export var volume_db: float = 0.0
# Nahodne stlmenie o 0..X dB pri kazdom prehrati (-X..0 dB).
@export_range(0.0, 6.0, 0.1) var volume_jitter_db: float = 1.0
# Nahodny pitch v rozsahu 1±X (0.03 = 0.97–1.03).
@export_range(0.0, 0.2, 0.005) var pitch_jitter: float = 0.03
# Max naraz hrajucich instancii TOHTO id — nad limit sa ukradne najstarsia vlastna.
@export var max_instances: int = 4
# Min rozostup (s) medzi dvoma spusteniami tohto id — tlmi "machine gun" efekt
# ked 10 jednotiek zasiahne v tom istom frame.
@export var min_interval: float = 0.05
# false = hra sa bez pozicie (stred, bez panningu/utlmu), aj ked caller poziciu posle.
@export var positional: bool = true
# Svetove px od stredu kamery. Dalej sa zvuk ani nespusti (neobsadi hlas).
@export var max_distance: float = 500.0
```

### 2. `scripts/AudioManager.gd`: SFX pool, `SoundData` scan, `play_sfx()`

Update the phase comment in the header: `play_sfx()` is now phase 2, and ambient is phase 3. Then add the following. Keep its structure; small idiomatic fixes are fine if you flag them in the plan.

```gdscript
const SOUNDS_PATH := "res://data/sounds/"
const SFX_POOL_SIZE := 16        # pozicne hlasy (AudioStreamPlayer2D)
const SFX_FLAT_POOL_SIZE := 4    # nepozicne SFX (positional=false / bez pozicie)

var _sounds: Dictionary = {}         # StringName -> SoundData
var _sfx_pool: Array[AudioStreamPlayer2D] = []
var _sfx_flat_pool: Array[AudioStreamPlayer] = []
# Co prave hra v ktorom hlase: player -> {"id", "prio", "start"}.
var _voice_meta: Dictionary = {}
var _last_played: Dictionary = {}    # id -> cas posledneho spustenia (s)
var _last_variant: Dictionary = {}   # id -> index poslednej varianty
var _warned: Dictionary = {}         # id -> true (kazde varovanie len raz)
```

In `_ready()`, after the existing pools:

```gdscript
	# SFX pool pauzuje spolu s hrou (rovnako ako voice) — boj zamrzne aj zvukovo.
	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p)
		_sfx_pool.append(p)
	for _i in SFX_FLAT_POOL_SIZE:
		_sfx_flat_pool.append(_make_player(BUS_SFX, Node.PROCESS_MODE_PAUSABLE))
	_scan_sounds()
```

New section:

```gdscript
# ---------------------------------------------------------------- SFX

# Jediny vstup pre herne zvuky. pos = Vector2.INF → bez pozicie.
# Prazdne id = ticho bez varovania (volajuci nemusia guardovat nenastavene polia).
func play_sfx(id: StringName, pos: Vector2 = Vector2.INF) -> void:
	if id == &"":
		return
	var def: SoundData = _sounds.get(id)
	if def == null:
		_warn_once(id, "neznamy sfx id")
		return
	if def.streams.is_empty():
		_warn_once(id, "SoundData nema ziadne streams (chyba asset)")
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(id, -1000.0)) < def.min_interval:
		return
	var positional := def.positional and pos != Vector2.INF
	if positional and _is_beyond_listener(pos, def.max_distance):
		return  # mimo dosahu — neobsadzuj hlas zvukom, ktory by nebolo pocut
	var player: Node = _acquire_voice(id, def, positional)
	if player == null:
		return  # vsetky hlasy hraju nieco dolezitejsie — novy zvuk sa zahodi
	_last_played[id] = now
	player.stop()
	player.stream = _pick_variant(id, def)
	player.bus = def.bus
	player.volume_db = def.volume_db - randf() * def.volume_jitter_db
	player.pitch_scale = 1.0 + randf_range(-def.pitch_jitter, def.pitch_jitter)
	if positional:
		player.global_position = pos
		player.max_distance = def.max_distance
	_voice_meta[player] = {"id": id, "prio": def.priority, "start": now}
	player.play()

# Poradie: (1) limit instancii tohto id → ukradni jeho najstarsiu instanciu,
# (2) volny hlas, (3) ukradni hlas s najnizsou prioritou (pri zhode najstarsi),
# ale len ak jeho priorita <= nova. Inak null (drop).
func _acquire_voice(id: StringName, def: SoundData, positional: bool) -> Node:
	var pool: Array = _sfx_pool if positional else _sfx_flat_pool
	var same: Array = []
	for p in pool:
		if p.playing and _voice_meta.get(p, {}).get("id") == id:
			same.append(p)
	if same.size() >= def.max_instances:
		return _oldest(same)
	for p in pool:
		if not p.playing:
			return p
	var victim: Node = null
	for p in pool:
		var m: Dictionary = _voice_meta[p]
		if m.prio > def.priority:
			continue
		if victim == null:
			victim = p
			continue
		var v: Dictionary = _voice_meta[victim]
		if m.prio < v.prio or (m.prio == v.prio and m.start < v.start):
			victim = p
	return victim

func _oldest(players: Array) -> Node:
	var best: Node = players[0]
	for p in players:
		if _voice_meta[p].start < _voice_meta[best].start:
			best = p
	return best

# Nahodna varianta, nikdy nie ta ista ako minule (pri 2+ variantach).
func _pick_variant(id: StringName, def: SoundData) -> AudioStream:
	var n := def.streams.size()
	if n == 1:
		return def.streams[0]
	var last: int = _last_variant.get(id, -1)
	var i: int
	if last < 0:
		i = randi() % n
	else:
		i = randi() % (n - 1)
		if i >= last:
			i += 1
	_last_variant[id] = i
	return def.streams[i]

# Listener 2D audia = stred obrazovky aktivnej Camera2D.
func _is_beyond_listener(pos: Vector2, max_dist: float) -> bool:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return false
	return cam.get_screen_center_position().distance_squared_to(pos) > max_dist * max_dist

func _warn_once(id: StringName, msg: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning("AudioManager: %s '%s'" % [msg, id])

# Rovnaky scan ako CardDB._scan_into() — vratane .remap v Android exporte.
func _scan_sounds() -> void:
	# ... copy the CardDB pattern: DirAccess over SOUNDS_PATH, strip ".remap",
	# load each "*.tres", require `res is SoundData`, push_error + skip on
	# duplicate id, store _sounds[res.id] = res.
```

Plan checks for this file:
- Confirm how `AudioStreamPlayer2D` measures distance and panning in Godot 4.7 when a `Camera2D` has `zoom = 3`: world pixels or screen pixels. Say whether `max_distance = 500` means world px (the map is about 780 world px wide; one screen is about 390 world px wide at zoom 3). If panning turns out to be almost inactive at this zoom, say so and propose the fix (the project setting `audio/general/2d_panning_strength`, or `panning_strength` per player). **Don't silently change it.**
- Confirm that an `AudioStreamPlayer2D` whose parent is a plain `Node` (the autoload) uses its `global_position` correctly and hears the root viewport's camera.

### 3. `scripts/arena/hero_data.gd` and `scripts/arena/unit_data.gd`: sound ids instead of streams

`hero_data.gd`:
- **Remove** `@export var attack_sound: AudioStream`.
- Add:

  ```gdscript
  # Id-cka SoundData (data/sounds/) — prehravane cez AudioManager.play_sfx().
  # attack_sfx hra v DAMAGE POINTE (dopad melee / vypustenie strely), nie na
  # zaciatku svihu — zruseny windup tak nikdy nevyda zvuk. &"" = ticho.
  @export var attack_sfx: StringName
  @export var death_sfx: StringName
  ```

- Leave `spawn_voice` as it is.

`unit_data.gd`: add the same two fields with the same comment.

### 4. Hero hooks: `player.gd` and `hero_dummy.gd` (the same change in both files)

- **Delete** `_play_attack_sound()` and its call in `update_attack_animation()`.
- In `_perform_attack()`, after the target validity checks:
  - **MELEE branch:** right after `target.take_damage(projectile_damage)` → `AudioManager.play_sfx(hero_data.attack_sfx, global_position)`.
  - **Ranged branch:** right before `fire_bolt(target)` → the same call.

  Guard with `if hero_data != null`, same as the existing spawn-voice line.
- In `die()`, directly after the `is_dead = true` line → `AudioManager.play_sfx(hero_data.death_sfx, global_position)` (same null guard).
- **Delete** the `AttackSfx` node from `scenes/arena/player.tscn` and from `scenes/arena/hero_dummy.tscn`, including any `ext_resource` used only by it. Nothing else changes in those scenes.

### 5. Unit and turret hooks

`unit.gd`:
- In `_resolve_attack_hit()`, after the `is_instance_valid(target) / _is_target_alive` early return and before `match attack_type` → `AudioManager.play_sfx(unit_data.attack_sfx, global_position)`. It plays once whether the unit is melee or ranged.
- In `die()`, directly after `is_dying = true` → `AudioManager.play_sfx(unit_data.death_sfx, global_position)`.
- Guard both with `if unit_data != null`.

`turret.gd`:
- Add `@export var destroyed_sfx: StringName = &"turret_destroyed"`. It's a script default, so no `.tscn` edits.
- In `_on_destroyed()`, at the top → `AudioManager.play_sfx(destroyed_sfx, global_position)`.
- **No firing sound for turrets** in this step.

### 6. NEW `data/sounds/*.tres` + data wiring

Create these `SoundData` resources. The file name is the id. Every `streams` path is under `res://assets/audio/sfx/`.

| file / id | streams | bus | priority | volume_db | max_instances | min_interval |
|---|---|---|---|---|---|---|
| `sword_hit` | `combat/melee/sword_hit_01…06.wav` | Combat | LOW | -6 | 3 | 0.05 |
| `hero_melee_hit` | the same 6 `sword_hit` files | Combat | HIGH | 0 | 2 | 0.05 |
| `arrow_shot` | `combat/ranged/arrow_shot_01…03.wav` | Combat | LOW | -6 | 3 | 0.05 |
| `unit_death` | `combat/death/unit_death_01.wav` | Combat | LOW | -4 | 2 | 0.1 |
| `zeus_bolt` | `heroes/zeus/zeus_bolt_travel.wav` | Combat | HIGH | 0 | 2 | 0.05 |
| `hero_death_greek` | `combat/death/hero_death_greek_01.wav` | Combat | CRITICAL | 0 | 1 | 0.5 |
| `turret_destroyed` | *(empty; asset not made yet)* | Combat | CRITICAL | 0 | 1 | 0.0 |

All other fields stay at their script defaults (jitter 1.0 dB / 0.03, `positional = true`, `max_distance = 500`).

**Why two ids share the sword files:** priority belongs to the event, not the file. A hero's hit must not be stolen by twelve hoplites.

Wire the ids into the data files:
- `hero_zeus.tres`: `attack_sfx = &"zeus_bolt"`, `death_sfx = &"hero_death_greek"`
- `hero_poseidon.tres`: `attack_sfx = &"hero_melee_hit"`, `death_sfx = &"hero_death_greek"`
- `greek_hoplite.tres`: `attack_sfx = &"sword_hit"`, `death_sfx = &"unit_death"`
- `greek_toxotes.tres`, `greek_gastraphetes.tres`: `attack_sfx = &"arrow_shot"`, `death_sfx = &"unit_death"`

When editing the hero/unit `.tres` files, touch only these fields and don't reorder existing lines. If `hero_zeus.tres` already has a `spawn_voice` sub-resource (I may have added it in the Inspector), keep it exactly as it is.

### 7. `scripts/arena/arena.gd`: one debug key

In `_input()`, next to the other debug keys:

```gdscript
		# --- DEBUG audio (docasne) — 10x sword_hit v jednom frame pri hracovi:
		# ma byt pocut max 3 (max_instances) a min_interval ich este preriedi ---
		if event.keycode == KEY_J:
			for _i in 10:
				AudioManager.play_sfx(&"sword_hit", player.global_position)
			print("[audio] 10x sword_hit spam")
```

## DO NOT TOUCH

- The music, UI, voice and volume code in `AudioManager.gd`, and the `MUSIC_TRACKS`/`UI_SOUNDS` tables. Moving those into `SoundData` is a later step.
- `spawn_voice` and `play_voice()`.
- `default_bus_layout.tres`, `settings.gd`, `audio_control.gd`, `setting_overlay.tscn`.
- `projectile.gd`: no impact sounds on projectiles.
- `BattleManager.gd`, `EnergySystem.gd`, `HealingSystem.gd`, `HeroAI.gd`, `base.gd`.
- Combat logic in every file: only the listed one-line sound calls get added. No reordering of damage, cooldown or cancel logic.
- The `.import` files under `assets/audio/`.

## Explicitly OUT of scope

- Ambient beds and random ambient emitters (phase 3)
- Sounds for: base destroyed (the match ends and the scene changes in the same frame, so that needs a stinger on `MatchEndScreen` instead), unit spawn or card deploy, spell cast, hero taking damage, turret firing, projectile impact. No assets exist for these yet.
- Moving `MUSIC_TRACKS`/`UI_SOUNDS` into `SoundData`
- Lowering music under critical sounds, a stereo on/off setting, any per-call priority override
- Growing the pool at runtime, or any stop-all/cleanup on scene change (sounds are short and can play out)

## VERIFY

Static checks:
- `grep -rn "attack_sound\|AttackSfx\|_play_attack_sound" scripts scenes data` → no results.
- `grep -rn "AudioManager.play_sfx" scripts` → only `player.gd`, `hero_dummy.gd`, `unit.gd`, `turret.gd`, `arena.gd` (debug). **No autoloads.**
- `ls data/sounds/` → exactly the 7 `.tres` files from step 6.
- `grep -n "attack_sfx\|death_sfx" data/heroes/*.tres data/units/*.tres` → 2 lines per file, 5 files.
- `git diff --stat` shows only the files named in steps 1–7 and the new `data/sounds/` files.

Runtime tests:
1. **Project load:** no errors. The only allowed warning is `turret_destroyed … chyba asset`, and only when a turret is destroyed, once per session.
2. **Zeus attack:** the bolt sound plays when the bolt is released, not at the start of the swing. Start a swing, then tap-move before the damage point: **no** sound.
3. **Poseidon (enemy) melee:** a sword hit plays only when the hit lands.
4. **Units:** hoplites clash with sword hits and archers/crossbows with arrow shots. The same sample never plays twice in a row, and pitch varies slightly.
5. **Limits:** press **J** → at most 3 overlapping sword hits, not 10 stacked (no loud spike or crackle). In a big fight (6+ units per side, both heroes), hero bolt and melee sounds stay audible over the unit noise.
6. **Positional:** with headphones, pan the camera so a fight is off to the left or right, and the sound follows that side. Pan far away and it gets quieter, then silent past `max_distance`. Report how far `500` feels in screens, and whether panning is noticeable at zoom 3.
7. **Deaths:** units play `unit_death`; either hero's death plays `hero_death_greek` (use **H** ×3 for the player).
8. **Pause:** open settings mid-fight → combat sounds pause, then resume on close. Menu taps still work.
9. **Volume:** the Effects slider scales combat sounds; Music and Voice don't affect them.
10. **Exit to menu mid-fight:** no errors, and nothing keeps looping.
11. **If you can, an Android build:** no audio crackle in a big fight.

Stop after this step and report: the diff summary, anything in the plan you changed (especially the zoom/panning findings), and any test you couldn't run.
