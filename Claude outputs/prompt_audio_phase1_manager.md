# Claude Code prompt — Audio phase 1: AudioManager autoload (buses, music, UI, voice, volumes)

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Right now the game's audio is:
- a `Music` autoload (`scenes/music.tscn`): a single `AudioStreamPlayer2D` on autoplay. Because it's positional, it's the wrong node type for music.
- one `$AttackSfx` node per hero.
- one volume slider (`audio_control.gd`) that writes straight to `AudioServer` and is hardcoded to `Settings.music_volume`. The saved volume only gets applied once the settings overlay has been instantiated.

This step adds **`AudioManager`**, a new autoload that becomes the single entry point for all audio. Phase 1 covers:
- the bus layout
- music with crossfade and a random track per context
- UI tap sounds wired to every button automatically
- a voice channel, plus a hero spawn voice line for the **local** hero only
- Music / SFX / Voice volume settings

The pooled positional combat SFX (`play_sfx`), priorities and `SoundDB` come in phase 2. **Not now.**

Design rule for everything in this step: audio is **presentation only and client-side**. `AudioManager` holds nodes. It is never called from the pure-logic autoloads (`EnergySystem`, `HealingSystem`, `HeroAI`), only from scene nodes and UI that react to events.

## Files to read first

- `project.godot` (the `[autoload]` and `[audio]` sections)
- `default_bus_layout.tres`
- `scenes/music.tscn`: read only; it's being retired
- `scripts/settings.gd`
- `scripts/ui/audio_control.gd`
- `scripts/ui/setting_overlay.gd`, `scenes/menu/setting_overlay.tscn`
- `scripts/ui/main_menu.gd`
- `scripts/arena/arena.gd`
- `scripts/ui/match_end_screen.gd`
- `scripts/arena/hero_data.gd`
- `scripts/arena/player.gd` (`configure()`, `_ready()`, `revive()`, `play_spawn_animation()`, `_play_attack_sound()`)
- `scripts/hud/HUD.gd`: read only; it shows how the tree gets paused while the settings overlay is open
- `scenes/menu/credits_overlay.tscn`: read only; `CloseCredits` gets a group (step 6)

Before planning, grep the whole project for `Music.`, `/root/Music` and `get_node("Music")`, and report every hit. If anything besides `project.godot` references the old autoload, list it in the plan.

## Changes

### 1. `default_bus_layout.tres`: full bus tree + limiter on Master

Target layout. Order matters: a bus can only send to a bus with a **lower** index.

| idx | name | send |
|---|---|---|
| 0 | Master (+ `AudioEffectHardLimiter`, default settings) | — |
| 1 | Music | Master |
| 2 | SFX | Master |
| 3 | Combat | SFX |
| 4 | UI | SFX |
| 5 | Environment | SFX |
| 6 | Voice | Master |

Keep the file's existing `uid`. Add the limiter as a `sub_resource` referenced by `bus/0/effect/0/effect`, with `bus/0/effect/0/enabled = true`. If you aren't sure of the exact serialization for bus 0's effect entry, say so in the plan and I'll add the limiter by hand in the Audio panel. **Don't guess.** `Combat` and `Environment` stay unused in this step. They exist now so phase 2 and 3 don't have to touch this file.

### 2. `scripts/settings.gd`: SFX and Voice volumes

Next to `music_volume`, add `sfx_volume: float = 1.0` and `voice_volume: float = 1.0`. Save and load them under the `"audio"` section, the same way as `music_volume`. Add `set_sfx_volume(val)` and `set_voice_volume(val)` that mirror `set_music_volume()` exactly (assign, `save_settings()`, `settings_changed.emit()`). No other changes.

### 3. NEW `scripts/AudioManager.gd`: the autoload

`extends Node`. No `class_name`, same as the other autoloads. Reference implementation below. Keep its structure; small idiomatic fixes are fine if you flag them in the plan.

```gdscript
extends Node

# AudioManager — jediny vstupny bod pre vsetok zvuk v hre (autoload).
# Prezentacna vrstva, ciste client-side: NIKDY sa nevola z "pure logic"
# autoloadov (EnergySystem / HealingSystem / HeroAI) — zvuky spustaju scene
# nody ako reakciu na udalosti, kazdy klient si ich prehra lokalne.
# Hlasitosti drzi Settings (single source of truth), tu sa len aplikuju na busy.
# Faza 1: music (crossfade), UI, voice, hlasitosti. play_sfx() + pool = faza 2.

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
const BUS_VOICE := &"Voice"

# TEMP (faza 1): kym nie je SoundDB, id → cesty su natvrdo tu.
# Viac ciest pod jednym id = nahodny vyber pri kazdom play_music().
const MUSIC_TRACKS := {
	&"menu": [
		"res://assets/audio/music/menu/music_menu_gods_descent.ogg",
		"res://assets/audio/music/menu/music_menu_timpani_rolls.ogg",
	],
	&"battle": [
		"res://assets/audio/music/battle/music_battle_arena_of_thunder.ogg",
		"res://assets/audio/music/battle/music_battle_gods_descent.ogg",
	],
}
const UI_SOUNDS := {
	&"select": "res://assets/audio/sfx/ui/ui_select.wav",
	&"close": "res://assets/audio/sfx/ui/ui_close.wav",
}

const UI_POOL_SIZE := 4
const DEFAULT_MUSIC_FADE := 1.0

# Skupiny na buttonoch (nastavit v .tscn / Inspectore):
# ui_sfx_close = zahra "close" namiesto "select", ui_sfx_none = ticho.
const GROUP_UI_CLOSE := &"ui_sfx_close"
const GROUP_UI_NONE := &"ui_sfx_none"

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _music_id: StringName = &""
var _music_tween: Tween

var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_next: int = 0
var _ui_cache: Dictionary = {}  # id -> AudioStream (lazy load)

var _voice: AudioStreamPlayer

func _ready() -> void:
	# Music a UI musia hrat aj pocas pauzy (settings overlay v arene pauzuje strom).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_player(BUS_MUSIC, Node.PROCESS_MODE_ALWAYS)
	_music_b = _make_player(BUS_MUSIC, Node.PROCESS_MODE_ALWAYS)
	_music_active = _music_a
	for i in UI_POOL_SIZE:
		_ui_pool.append(_make_player(BUS_UI, Node.PROCESS_MODE_ALWAYS))
	# Voice sa pauzuje spolu s hrou — hlaska boha nema dohravat cez pause menu.
	_voice = _make_player(BUS_VOICE, Node.PROCESS_MODE_PAUSABLE)

	_apply_volumes()
	Settings.settings_changed.connect(_apply_volumes)
	# Auto-wiring tap zvuku na kazdy button v kazdej scene — ziadne rucne connecty.
	get_tree().node_added.connect(_on_node_added)

func _make_player(bus: StringName, mode: Node.ProcessMode) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.process_mode = mode
	add_child(p)
	return p

# ---------------------------------------------------------------- MUSIC

# Rovnake id ako prave hrajuce = no-op (MainMenu → PreMatchFlow → MainMenu
# nerestartuje track). Ine id = crossfade na nahodny track z MUSIC_TRACKS.
func play_music(id: StringName, fade: float = DEFAULT_MUSIC_FADE) -> void:
	if id == _music_id and _music_active.playing:
		return
	var paths: Array = MUSIC_TRACKS.get(id, [])
	if paths.is_empty():
		push_warning("AudioManager: neznamy music id '%s'" % id)
		return
	var stream := load(paths.pick_random()) as AudioStream
	if stream == null:
		push_warning("AudioManager: music stream sa nepodarilo nacitat (%s)" % id)
		return
	_music_id = id
	var old := _music_active
	var new := _music_b if old == _music_a else _music_a
	if _music_tween != null:
		_music_tween.kill()
	new.stream = stream
	new.volume_linear = 0.0
	new.play()
	_music_active = new
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(new, "volume_linear", 1.0, fade)
	if old.playing:
		_music_tween.tween_property(old, "volume_linear", 0.0, fade)
	_music_tween.chain().tween_callback(old.stop)

func stop_music(fade: float = DEFAULT_MUSIC_FADE) -> void:
	_music_id = &""
	if _music_tween != null:
		_music_tween.kill()
	var p := _music_active
	_music_tween = create_tween()
	_music_tween.tween_property(p, "volume_linear", 0.0, fade)
	_music_tween.tween_callback(p.stop)

# ---------------------------------------------------------------- UI

# Round-robin pool — pri 5. rychlom tapnuti sa ukradne najstarsi hlas.
# Bez pitch/volume jitteru: UI zvuky maju byt konzistentne.
func play_ui(id: StringName) -> void:
	var stream := _get_ui_stream(id)
	if stream == null:
		return
	var p := _ui_pool[_ui_next]
	_ui_next = (_ui_next + 1) % UI_POOL_SIZE
	p.stream = stream
	p.play()

func _get_ui_stream(id: StringName) -> AudioStream:
	if _ui_cache.has(id):
		return _ui_cache[id]
	var path: String = UI_SOUNDS.get(id, "")
	if path == "":
		push_warning("AudioManager: neznamy UI zvuk '%s'" % id)
		return null
	var s := load(path) as AudioStream
	_ui_cache[id] = s
	return s

func _on_node_added(node: Node) -> void:
	if not (node is BaseButton or node is TouchScreenButton):
		return
	# groupy z .tscn su priradene uz pri instantiate, teda pred node_added
	if node.is_in_group(GROUP_UI_NONE) or node.has_meta(&"_ui_sfx_wired"):
		return
	node.set_meta(&"_ui_sfx_wired", true)  # guard proti dvojitemu connectu pri re-add
	var id := &"close" if node.is_in_group(GROUP_UI_CLOSE) else &"select"
	node.pressed.connect(play_ui.bind(id))

# ---------------------------------------------------------------- VOICE

# Max jedna hlaska naraz — nova prerusi staru. Stream moze byt
# AudioStreamRandomizer (nahodna varianta pri kazdom play()).
func play_voice(stream: AudioStream) -> void:
	if stream == null:
		return
	_voice.stop()
	_voice.stream = stream
	_voice.play()

# ---------------------------------------------------------------- VOLUME

# Linearna hodnota 0..1 (slider). Uklada Settings, aplikuje _apply_volumes()
# cez settings_changed.
func set_music_volume(linear: float) -> void:
	Settings.set_music_volume(linear)

func set_sfx_volume(linear: float) -> void:
	Settings.set_sfx_volume(linear)

func set_voice_volume(linear: float) -> void:
	Settings.set_voice_volume(linear)

# Genericke verzie pre audio_control.gd slider (audio_bus_name export).
func set_volume(bus: StringName, linear: float) -> void:
	match bus:
		BUS_MUSIC: set_music_volume(linear)
		BUS_SFX: set_sfx_volume(linear)
		BUS_VOICE: set_voice_volume(linear)
		_: push_warning("AudioManager: bus '%s' nema volume nastavenie" % bus)

func get_volume(bus: StringName) -> float:
	match bus:
		BUS_MUSIC: return Settings.music_volume
		BUS_SFX: return Settings.sfx_volume
		BUS_VOICE: return Settings.voice_volume
	return 1.0

func _apply_volumes() -> void:
	_apply_bus(BUS_MUSIC, Settings.music_volume)
	_apply_bus(BUS_SFX, Settings.sfx_volume)
	_apply_bus(BUS_VOICE, Settings.voice_volume)

func _apply_bus(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		push_warning("AudioManager: bus '%s' neexistuje" % bus)
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	if linear > 0.001:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
```

Plan checks for this file:
- Confirm that `AudioStreamPlayer.volume_linear` exists in Godot 4.7. If it doesn't, tween `volume_db` using `linear_to_db`, and floor it at -80 dB instead of `linear_to_db(0)`.
- Confirm that a Tween created by this `PROCESS_MODE_ALWAYS` node keeps running while the tree is paused.

### 4. `project.godot`: swap the autoloads

- Remove the `Music="*uid://cj52s8x0yvd85"` line.
- Add `AudioManager="*res://scripts/AudioManager.gd"` on the line **directly after** `Settings=`. `AudioManager._ready()` reads `Settings`, and autoloads become ready in listed order.
- Change nothing else in `project.godot`.
- **Do not delete** `scenes/music.tscn` or anything in `assets/music/` or `assets/sounds/`. I'll clean those up myself in the editor.

### 5. `scripts/ui/audio_control.gd`: one generic volume slider

- Keep `@export var audio_bus_name: String` (existing `.tscn` values stay valid) and the touch handling (`_gui_input`, `_apply_touch_position`) unchanged.
- In `_ready()`: `set_value_no_signal(AudioManager.get_volume(StringName(audio_bus_name)))`, then `value_changed.connect(_on_value_changed)`. This is a code connection, per project convention. Using `set_value_no_signal` means opening the overlay doesn't trigger a save.
- `_on_value_changed(val)` becomes a single line: `AudioManager.set_volume(StringName(audio_bus_name), val)`. Remove the direct `AudioServer` calls and the `audio_bus_id` variable.
- Delete the old commented-out block at the bottom of the file.
- Add a short comment at the top (Slovak/English style): one slider script for all volumes; `audio_bus_name` picks Music/SFX/Voice; the value lives in Settings and `AudioManager` applies it.

### 6. `scenes/menu/setting_overlay.tscn`: three volume sliders

Inside `SettingsContent`, directly after `AudioLabel` and before `LockCameraRow`, the order becomes:

`AudioLabel` (unchanged) → `MusicLabel` → `AudioControl` (existing node, unchanged, `audio_bus_name = "Music"`) → `SfxLabel` → `SfxControl` → `VoiceLabel` → `VoiceControl`

- **The three labels** ("Music", "Effects", "Voice"): `Label`s using exactly the same theme overrides as `LockCameraLabel` (font, size 20, colour, shadow offsets).
- **`SfxControl` / `VoiceControl`:** `HSlider`s copied from `AudioControl` (same `process_mode = 3`, `max_value`, `step`, `value`, script), with `audio_bus_name = "SFX"` / `"Voice"`.
- **New `unique_id`s:** every new node gets one that isn't used anywhere else in the file.
- **Remove the connection:** delete the `[connection signal="value_changed" … AudioControl …]` line. Step 5 now connects in code, and leaving it would double-connect.
- **Close buttons:** add `groups=["ui_sfx_close"]` to the `CloseSettings` node here, and to the `CloseCredits` node in `scenes/menu/credits_overlay.tscn`. That's the only change to `credits_overlay.tscn`.

### 7. Music call sites

- `scripts/ui/main_menu.gd::_ready()` → add `AudioManager.play_music(&"menu")`.
- `scripts/arena/arena.gd::_ready()` → add `AudioManager.play_music(&"battle")` as the last line (after `EnergySystem.start()`).
- `scripts/ui/match_end_screen.gd::_ready()` → add `AudioManager.play_music(&"menu")`.
- `PreMatchFlow`: no change. Menu music keeps playing because of the same-id no-op.

### 8. Spawn voice line (local hero only)

- **`scripts/arena/hero_data.gd`:** after `attack_sound`, add:

  ```gdscript
  # Hlaska boha pri spawne/respawne LOKALNEHO hrdinu (len player.gd, nie
  # hero_dummy). Typicky AudioStreamRandomizer s viacerymi variantami —
  # AudioManager.play_voice() si pri kazdom prehrati vyberie nahodnu.
  @export var spawn_voice: AudioStream
  ```

- **`scripts/arena/player.gd::play_spawn_animation()`:** as the **first** statement, add

  ```gdscript
  	if hero_data != null:
  		AudioManager.play_voice(hero_data.spawn_voice)  # null = ticho, play_voice to osetri
  ```

  This function runs both from `_ready()` (first spawn) and from `revive()` (respawn), so both cases are covered. `hero_dummy.gd` is **not** touched: the enemy god stays silent.

## DO NOT TOUCH

- `$AttackSfx`, `_play_attack_sound()` and `HeroData.attack_sound`. They move to `play_sfx()` in phase 2.
- `hero_dummy.gd`, `unit.gd`, `turret.gd`, projectiles: no combat sounds in this step.
- `BattleManager.gd`, `EnergySystem.gd`, `HealingSystem.gd`, `HeroAI.gd`: no audio calls in pure-logic autoloads, ever.
- `HUD.gd` pause logic, the `SettingsOverlay` open/close logic, `main_menu.gd` navigation.
- The `.import` files under `assets/audio/`: import settings are already done.
- `data/heroes/*.tres`: I'll wire `spawn_voice` myself in the Inspector.

## Explicitly OUT of scope

- `play_sfx()`, the positional `AudioStreamPlayer2D` pool, priorities and voice stealing, `SoundData`/`SoundDB`
- Ambient beds and random ambient emitters
- Lowering music volume under voice lines or ultimates
- A stereo on/off setting, or a master volume slider
- Throttling `Settings` saves while a slider is dragged (existing behaviour, left as is)
- Moving `MUSIC_TRACKS`/`UI_SOUNDS` out of code: that's `SoundDB` in phase 2

## VERIFY

Static checks:
- `grep -rn "Music\.\|/root/Music" scripts scenes` → no results.
- `grep -n "AudioManager" project.godot` → one line, directly after `Settings=`.
- `grep -rn "AudioServer" scripts` → only in `AudioManager.gd`.
- `grep -rn "AudioManager\." scripts` → only `main_menu.gd`, `arena.gd`, `match_end_screen.gd`, `player.gd`, `audio_control.gd`. **No** logic autoloads.
- `grep -n "value_changed" scenes/menu/setting_overlay.tscn` → no results.
- `grep -n "ui_sfx_close" scenes/menu/*.tscn` → `CloseSettings` and `CloseCredits`.
- `git diff --stat` shows only the files named in steps 1–8 plus the new `scripts/AudioManager.gd`.

Editor checks:
- The Audio bottom panel shows 7 buses in the table's order and sends, with a HardLimiter on Master.
- No errors or warnings in the Output panel on project load.

Runtime tests. Before these, I'll create an `AudioStreamRandomizer` on `hero_zeus.tres → spawn_voice` with `zeus_spawn_01`/`02`.
1. **Boot → MainMenu:** a menu track fades in. Restart a few times and both menu tracks turn up.
2. **Menu buttons:** every button (nav rail, top bar, Battle, Settings) plays `ui_select`. The settings close X and the credits close X play `ui_close`. Pressing Battle keeps the tap sound playing through the scene change, with no cut-off.
3. **MainMenu → PreMatchFlow → arena:** menu music continues through PreMatchFlow without restarting, then crossfades to a battle track when the arena loads.
4. **Arena start:** the Zeus spawn line plays once, at the start of the spawn animation. Press **H** three times to die, then wait for the respawn: a line plays again, and over a few deaths both variants turn up. The enemy (Poseidon) never plays a spawn line.
5. **Pause:** music keeps playing and UI taps work. Pause during a spawn line: the voice pauses, then resumes on unpause.
6. **Settings sliders (menu and in-match pause):** Music, Effects and Voice each change only their own bus. Taps get quieter with Effects, the spawn line with Voice. At 0 each is fully muted. Restart the game: all three volumes are restored **before** the settings overlay is ever opened (menu music already starts at the saved level).
7. **Exit match → MainMenu** (HUD exit and via MatchEndScreen): music crossfades back to a menu track with no silence gap and no overlapping double music.
8. Enter and leave the arena 3 times in a row → no stacked music, no errors.

Stop after this step and report: the diff summary, anything in the plan you changed (especially the step 1 bus serialization and the `volume_linear` check), and any test you couldn't run.
