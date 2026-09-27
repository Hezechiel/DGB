# Claude Code prompt — Audio phase 3b: voice via SoundData, announcer queue + music ducking, victory/defeat stingers, first blood

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

**Prerequisite:** phase 3a (ambient) has landed.

## Context

Voice is the last part of the game's audio that doesn't use `SoundData`: `HeroData.spawn_voice` is a raw `AudioStream`, and `play_voice(stream)` plays it on the single `_voice` player. This step:

1. **Moves voice onto `SoundData` ids.** `play_voice(id)`, `HeroData.spawn_voice: StringName`, and a `zeus_spawn.tres` with both spawn lines. Variant picking uses the existing never-twice-in-a-row logic.
2. **Adds an announcer channel.** `play_announcer(id)` gets its own player and a short **queue**, so announcer lines never cut each other off and never cut off a god's voice line. While the announcer speaks, **music ducks** by a few dB.
3. **Adds stingers.** `play_stinger(id, then_music)` fades the battle music out, plays a short victory or defeat cue on the Music bus, then starts the given music. It's used by `MatchEndScreen`.
4. **Adds first blood.** A small `MatchAnnouncer` node in the arena listens for `BattleManager.hero_died` and plays "first blood" on the first hero death of the match.

The architecture rules still apply. Audio is client-side presentation. `BattleManager` never calls `AudioManager`: the announcer is a **self-subscribing scene node**, the same pattern as `death_telegraph.gd` and the respawn counters. It lives with the arena scene, so its per-match state (first blood already said) resets for free with every new arena.

## Files to read first

- `scripts/AudioManager.gd` (whole file: `play_voice()`, `play_music()`, `stop_music()`, `_pick_variant()`, `get_sound()`, `_apply_bus()`)
- `scripts/sound_data.gd`
- `data/sounds/sword_hit.tres`: read only; the format reference
- `scripts/arena/hero_data.gd`, `data/heroes/hero_zeus.tres`
- `scripts/arena/player.gd` (`play_spawn_animation()`: the existing `play_voice` call)
- `scripts/ui/match_end_screen.gd`
- `scripts/BattleManager.gd`: read only (`hero_died` signal, `last_winner` values `"player"`/`"enemy"`/`"draw"`)
- `scripts/arena/arena.gd` (`_ready()`, where `EnemyCardAI.new()` is added)
- `scripts/arena/ui/death_telegraph.gd`: read only; the self-subscribe pattern to copy

## Changes

### 1. `scripts/sound_data.gd`: two more buses

Extend the bus enum to `@export_enum("Combat", "Environment", "Voice", "Music") var bus: String = "Combat"`. Add one comment line: Voice/Music ids are played through `play_voice`/`play_announcer`/`play_stinger`, which use `volume_db` and variants but **ignore** jitter, `positional` and the pool. No other changes.

### 2. `scripts/AudioManager.gd`

**Voice by id.** Replace `play_voice(stream: AudioStream)` with:

```gdscript
# Hlaska boha (spawn a pod.) — max jedna naraz, nova prerusi staru.
# Varianty z SoundData (bez opakovania), jitter sa pri hlase NEPOUZIVA.
func play_voice(id: StringName) -> void:
	var def := _get_playable(id)
	if def == null:
		return
	_voice.stop()
	_voice.stream = _pick_variant(id, def)
	_voice.volume_db = def.volume_db
	_voice.play()
```

**Shared lookup** (used by voice, announcer and stinger; `play_sfx` stays as it is):

```gdscript
# get_sound() + kontrola prazdnych streams (raz varuje). &"" = ticho bez varovania.
func _get_playable(id: StringName) -> SoundData:
	var def := get_sound(id)
	if def == null:
		return null
	if def.streams.is_empty():
		_warn_once(id, "SoundData nema ziadne streams (chyba asset)")
		return null
	return def
```

**Announcer + queue + ducking.** New fields, created in `_ready()` next to `_voice`:

```gdscript
const ANNOUNCER_QUEUE_MAX := 2      # viac cakajucich hlasok sa zahodi — stare spravy su bezcenne
const MUSIC_DUCK_DB := -8.0
const MUSIC_DUCK_TIME := 0.25

var _announcer: AudioStreamPlayer   # BUS_VOICE, PROCESS_MODE_PAUSABLE, finished → _on_announcer_finished
var _announcer_queue: Array[StringName] = []
var _music_duck_db: float = 0.0
var _duck_tween: Tween
```

```gdscript
# Hlasatel — vlastny prehravac, hlasky sa NEPRERUSUJU: ak prave hovori,
# nova ide do kratkej fronty. Pocas hlasky je hudba stlmena (duck).
func play_announcer(id: StringName) -> void:
	if id == &"":
		return
	if _announcer.playing:
		if _announcer_queue.size() < ANNOUNCER_QUEUE_MAX:
			_announcer_queue.append(id)
		return
	_start_announcer(id)

func _start_announcer(id: StringName) -> void:
	var def := _get_playable(id)
	if def == null:
		_on_announcer_finished()  # pokracuj frontou, nezasekni sa na chybajucom assete
		return
	_announcer.stream = _pick_variant(id, def)
	_announcer.volume_db = def.volume_db
	_announcer.play()
	_set_music_duck(true)

func _on_announcer_finished() -> void:
	if _announcer_queue.is_empty():
		_set_music_duck(false)
		return
	_start_announcer(_announcer_queue.pop_front())

# Volane pri odchode z areny — ziadna hlaska zapasu nedohrava do menu.
func stop_announcer() -> void:
	_announcer_queue.clear()
	_announcer.stop()
	_set_music_duck(false)

func _set_music_duck(on: bool) -> void:
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck_db, _music_duck_db, MUSIC_DUCK_DB if on else 0.0, MUSIC_DUCK_TIME)

func _set_duck_db(v: float) -> void:
	_music_duck_db = v
	_apply_bus(BUS_MUSIC, Settings.music_volume)
```

In `_apply_bus()`, add the duck offset **only for the Music bus**: `linear_to_db(linear) + (_music_duck_db if bus == BUS_MUSIC else 0.0)`. Muting at 0 stays exactly as it is now.

**Stinger.** New fields, created in `_ready()`:

```gdscript
var _stinger: AudioStreamPlayer     # BUS_MUSIC, PROCESS_MODE_ALWAYS, finished → _on_stinger_finished
var _music_after_stinger: StringName = &""
```

```gdscript
# Kratka hudobna fraza (vitazstvo/prehra). Aktualna hudba rychlo odide,
# stinger zahra raz, potom sa spusti then_music (ak je zadane).
# Chybajuci asset → rovno then_music, nic sa nezasekne.
func play_stinger(id: StringName, then_music: StringName = &"") -> void:
	var def := _get_playable(id)
	if def == null:
		if then_music != &"":
			play_music(then_music)
		return
	stop_music(0.3)
	_music_after_stinger = then_music
	_stinger.stream = _pick_variant(id, def)
	_stinger.volume_db = def.volume_db
	_stinger.play()

func _on_stinger_finished() -> void:
	var next := _music_after_stinger
	_music_after_stinger = &""
	if next != &"":
		play_music(next)
```

At the very top of `play_music()`, before the same-id check, add: if `_stinger.playing` → `_stinger.stop()` and `_music_after_stinger = &""`. Explicit music always wins, e.g. pressing Menu mid-stinger. The same-id check itself stays unchanged.

Update the header comment: phase 3b = voice by id, announcer + queue + duck, stingers.

### 3. Hero data: spawn voice by id

- `hero_data.gd`: change `@export var spawn_voice: AudioStream` → `@export var spawn_voice: StringName`. Update its comment: it's a `SoundData` id on the Voice bus, variants live in `SoundData.streams`, and `&""` means silence.
- `hero_zeus.tres`: add `spawn_voice = &"zeus_spawn"`. Touch nothing else in the file.
- `player.gd`: the existing call `AudioManager.play_voice(hero_data.spawn_voice)` stays. Only fix its trailing comment (`null` → `&""`).

### 4. NEW `data/sounds/` voice / announcer / stinger `SoundData`

Same format as `sword_hit.tres`. For all of these: `volume_jitter_db = 0.0`, `pitch_jitter = 0.0`, `positional = false`, `max_instances = 1`, `min_interval = 0.0`.

| file / id | streams (under `res://assets/audio/`) | bus | priority | volume_db |
|---|---|---|---|---|
| `zeus_spawn` | `voice/heroes/zeus/zeus_spawn_01.ogg`, `zeus_spawn_02.ogg` | Voice | CRITICAL | 0 |
| `announcer_first_blood` | `voice/announcer/announcer_first_blood_01.ogg` | Voice | CRITICAL | 0 |
| `stinger_victory` | `music/stingers/stinger_victory.ogg` | Music | CRITICAL | 0 |
| `stinger_defeat` | `music/stingers/stinger_defeat.ogg` | Music | CRITICAL | 0 |
| `base_destroyed` | `sfx/combat/structures/base_destroyed_01.wav` | Combat | CRITICAL | 0 |

`base_destroyed` is the exception to the voice-style defaults above: keep `volume_jitter_db`/`pitch_jitter` at the script defaults. It's played through `play_sfx()` with no position (see step 7).

Also fill the existing **`data/sounds/turret_destroyed.tres`**: set `streams` to `[sfx/combat/structures/turret_destroyed_01.wav]`. Don't change any of its other fields.

### 5. NEW `scripts/arena/match_announcer.gd`

```gdscript
extends Node
class_name MatchAnnouncer

# Hlasatel zapasu — samostatny konzument BattleManager signalov (self-subscribe
# v _ready, rovnaky vzor ako death_telegraph / respawn countery). BattleManager
# o zvuku nevie nic. Zije so scenou areny → per-match stav sa resetuje sam.
# Dalsie hlasky (veza padla, double kill...) pribudnu sem, ked budu assety.

var _first_blood_done: bool = false

func _ready() -> void:
	BattleManager.hero_died.connect(_on_hero_died)

func _on_hero_died(_team: String, _respawn_seconds: int) -> void:
	if _first_blood_done:
		return
	_first_blood_done = true
	AudioManager.play_announcer(&"announcer_first_blood")
```

### 6. `scripts/arena/arena.gd`

- In `_ready()`, directly after `add_child(EnemyCardAI.new())` → `add_child(MatchAnnouncer.new())`.
- Add `_exit_tree()` that calls `AudioManager.stop_announcer()`, with a one-line comment: no announcer line carries into the menu or `MatchEndScreen`. If `arena.gd` already has an `_exit_tree()`, append the call there instead.

### 7. `scripts/ui/match_end_screen.gd`

Replace `AudioManager.play_music(&"menu")` in `_ready()` with:

```gdscript
	# Vitazstvo/prehra z pohladu LOKALNEHO hraca (last_winner je "player"/"enemy"/"draw").
	# Rucanie zakladne — v arene sa nestihne (zmena sceny v tom istom frame
	# ako on_base_destroyed), preto hra az tu, nepozicne, pred stingerom.
	if winner == "player" or winner == "enemy":
		AudioManager.play_sfx(&"base_destroyed")
	match winner:
		"player":
			AudioManager.play_stinger(&"stinger_victory", &"menu")
		"enemy":
			AudioManager.play_stinger(&"stinger_defeat", &"menu")
		_:
			AudioManager.play_music(&"menu")
```

## DO NOT TOUCH

- `play_sfx()`, the SFX pools, priority and stealing, `AmbientEmitter`, UI sounds, volume settings UI
- `BattleManager.gd` and every logic autoload. **No** `AudioManager` calls may be added there.
- `hero_dummy.gd`: the enemy god stays silent on spawn
- `death_telegraph.gd`, `match_info_bar.gd`, `card_hand.gd`: existing `hero_died` consumers stay as they are
- `MUSIC_TRACKS` / `UI_SOUNDS` tables
- Every `.import` file and every existing asset

## Explicitly OUT of scope

- Sounds for a base under attack or a turret being hit (only the destroyed events)
- Other announcer lines (tower destroyed, double kill, victory/defeat voice): no assets yet. `MatchAnnouncer` is the place for them later.
- Kill attribution (first blood currently fires on **any** first hero death, including the debug **H** key)
- Lowering music for hero voice lines or combat (only the announcer does it)
- Moving `MUSIC_TRACKS` / `UI_SOUNDS` into `SoundData`
- Localisation / subtitles for announcer lines

## VERIFY

Static checks:
- `grep -rn "play_voice(" scripts` → the definition in `AudioManager.gd` + the single call in `player.gd`. No `AudioStream` argument anywhere.
- `grep -n "spawn_voice" scripts/arena/hero_data.gd data/heroes/*.tres` → a `StringName` export, and `&"zeus_spawn"` in `hero_zeus.tres` only.
- `grep -rn "AudioManager\." scripts/BattleManager.gd scripts/EnergySystem.gd scripts/HealingSystem.gd scripts/HeroAI.gd` → no results.
- `grep -rn "hero_died.connect" scripts` → the existing consumers + `match_announcer.gd`.
- `ls data/sounds/` → the previous 10 files + 5 new ones (`zeus_spawn`, `announcer_first_blood`, `stinger_victory`, `stinger_defeat`, `base_destroyed`).
- `git diff --stat` shows only `sound_data.gd`, `AudioManager.gd`, `hero_data.gd`, `hero_zeus.tres`, `player.gd` (comment only), `arena.gd`, `match_end_screen.gd`, `turret_destroyed.tres`, and the new `match_announcer.gd` + 5 `.tres` files.

Runtime tests:
1. **Spawn voice:** at match start Zeus says one of the two lines. Die 4× with **H** → every respawn plays a line and never the same one twice in a row. The enemy never speaks.
2. **First blood:** the first hero death of the match (either side, **H** is fine) → the announcer says "first blood" and the battle music audibly dips, then comes back smoothly when the line ends. Later deaths → no more first blood. New match → it works again.
3. **No cutting off:** die with **H** right when a spawn line is playing → first blood plays **on top of** the god line; neither cuts the other. (Queue test: temporarily call `play_announcer(&"announcer_first_blood")` 3× in a row from the debug key J → it's heard at most 2 more times, one after another, never overlapping. Remove the temporary call afterwards.)
4. **Victory:** destroy the enemy base → on `MatchEndScreen` the battle music fades out fast, the victory stinger plays once, then menu music starts. Press Menu **mid-stinger** → the stinger stops and menu music plays; there's never a stinger and music together or two music tracks at once.
5. **Defeat:** lose a match → the base collapse plays, then the defeat stinger, then menu music. (Victory also plays the collapse before its stinger.) Destroy a turret → the rubble sound plays at the turret, and there's no more `turret_destroyed` warning.
6. **Draw** (timer runs out) → menu music directly.
7. **Leave mid-announcer:** exit via HUD while "first blood" is playing → it stops immediately and the music isn't left ducked in the menu.
8. **Pause:** the announcer pauses with the game. Music stays ducked while paused and returns to normal after the line finishes.
9. **Music slider** while ducked → volume changes correctly and the duck offset still applies on top.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
