extends Node

# AudioManager — jediny vstupny bod pre vsetok zvuk v hre (autoload).
# Prezentacna vrstva, ciste client-side: NIKDY sa nevola z "pure logic"
# autoloadov (EnergySystem / HealingSystem / HeroAI) — zvuky spustaju scene
# nody ako reakciu na udalosti, kazdy klient si ich prehra lokalne.
# Hlasitosti drzi Settings (single source of truth), tu sa len aplikuju na busy.
# Faza 1: music (crossfade), UI, voice, hlasitosti. Faza 2: play_sfx() + SFX pool (SoundData). Faza 3a: ambient (AmbientEmitter, na map scene, nie tu). Faza 3b: voice cez id, announcer fronta + duck hudby, stingery.

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

const ANNOUNCER_QUEUE_MAX := 2      # viac cakajucich hlasok sa zahodi — stare spravy su bezcenne
const MUSIC_DUCK_DB := -8.0
const MUSIC_DUCK_TIME := 0.25

var _announcer: AudioStreamPlayer   # BUS_VOICE, PROCESS_MODE_PAUSABLE, finished → _on_announcer_finished
var _announcer_queue: Array[StringName] = []
var _music_duck_db: float = 0.0
var _duck_tween: Tween

var _stinger: AudioStreamPlayer     # BUS_MUSIC, PROCESS_MODE_ALWAYS, finished → _on_stinger_finished
var _music_after_stinger: StringName = &""

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
	_announcer = _make_player(BUS_VOICE, Node.PROCESS_MODE_PAUSABLE)
	_announcer.finished.connect(_on_announcer_finished)
	# Stinger hra aj pocas pauzy (napr. MatchEndScreen moze pauzu zdedit) — ALWAYS.
	_stinger = _make_player(BUS_MUSIC, Node.PROCESS_MODE_ALWAYS)
	_stinger.finished.connect(_on_stinger_finished)

	# SFX pool pauzuje spolu s hrou (rovnako ako voice) — boj zamrzne aj zvukovo.
	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(p)
		_sfx_pool.append(p)
	for _i in SFX_FLAT_POOL_SIZE:
		_sfx_flat_pool.append(_make_player(BUS_SFX, Node.PROCESS_MODE_PAUSABLE))
	_scan_sounds()

	_apply_volumes()
	Settings.settings_changed.connect(_apply_volumes)
	# Auto-wiring tap zvuku na kazdy button v kazdej scene — ziadne rucne connecty.
	get_tree().node_added.connect(_on_node_added)
	# Boot scena (MainMenu) vstupi do stromu SPOLU s autoloadmi — vsetky jej
	# node_added prebehnu este pred tymto _ready(), takze connect vyssie ich
	# nezachyti. Preto jednorazovo prejdeme uzly, ktore uz v strome su.
	# Dvojite zapojenie nehrozi — _on_node_added() ma guard cez meta _ui_sfx_wired.
	for n in get_tree().root.find_children("*", "", true, false):
		_on_node_added(n)

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
	if _stinger.playing:
		_stinger.stop()
		_music_after_stinger = &""
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

# get_sound() + kontrola prazdnych streams (raz varuje). &"" = ticho bez varovania.
func _get_playable(id: StringName) -> SoundData:
	var def := get_sound(id)
	if def == null:
		return null
	if def.streams.is_empty():
		_warn_once(id, "SoundData nema ziadne streams (chyba asset)")
		return null
	return def

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

# Verejny lookup SoundData pre nody, ktore si prehravaju zvuk samy (ambient bed).
# Neznáme id = raz varuje a vrati null; prazdne id = ticho, null bez varovania.
func get_sound(id: StringName) -> SoundData:
	if id == &"":
		return null
	var def: SoundData = _sounds.get(id)
	if def == null:
		_warn_once(id, "neznamy sound id")
	return def

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
	var dir := DirAccess.open(SOUNDS_PATH)
	if dir == null:
		push_error("AudioManager: cannot open directory " + SOUNDS_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".remap"):
				file_name = file_name.substr(0, file_name.length() - len(".remap"))
			if file_name.ends_with(".tres"):
				_load_sound(SOUNDS_PATH + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

func _load_sound(path: String) -> void:
	var res := load(path)
	if res == null or not (res is SoundData):
		push_error("AudioManager: failed to load SoundData at " + path)
		return
	var id: StringName = res.id
	if _sounds.has(id):
		push_error("AudioManager: duplicate sound id '%s' (path %s)" % [id, path])
		return
	_sounds[id] = res

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
		var db := linear_to_db(linear) + (_music_duck_db if bus == BUS_MUSIC else 0.0)
		AudioServer.set_bus_volume_db(idx, db)
