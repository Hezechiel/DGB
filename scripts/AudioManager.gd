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
	for _i in UI_POOL_SIZE:
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
	var next_player := _music_b if old == _music_a else _music_a
	if _music_tween != null:
		_music_tween.kill()
	next_player.stream = stream
	next_player.volume_linear = 0.0
	next_player.play()
	_music_active = next_player
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(next_player, "volume_linear", 1.0, fade)
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
	# Object.connect(&"pressed", ...) namiesto node.pressed.connect(...): node je
	# staticky typovany ako Node a ten ziadny "pressed" signal nema — typovany
	# pristup by bol compile error. BaseButton aj TouchScreenButton ten signal maju.
	node.connect(&"pressed", play_ui.bind(id))

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
