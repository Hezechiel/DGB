extends Node

# Persistentne nastavenia hry — ulozene na disk cez ConfigFile
# Nacita sa pri starte, ulozi sa pri kazdej zmene hodnoty

signal settings_changed

const SAVE_PATH := "user://settings.cfg"

# --- gameplay ---
var lock_camera: bool = false

# --- audio ---
var music_volume: float = 1.0

func _ready() -> void:
	load_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "lock_camera", lock_camera)
	cfg.set_value("audio", "music_volume", music_volume)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("Settings: nepodarilo sa ulozit nastavenia, chyba: " + str(err))

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		# subor este neexistuje — defaulty zostanu, nic sa nedeje
		return
	lock_camera = cfg.get_value("gameplay", "lock_camera", false)
	music_volume = cfg.get_value("audio", "music_volume", 1.0)

func set_lock_camera(val: bool) -> void:
	lock_camera = val
	save_settings()
	settings_changed.emit()

func set_music_volume(val: float) -> void:
	music_volume = val
	save_settings()
	settings_changed.emit()
