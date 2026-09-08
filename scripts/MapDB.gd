extends Node

# MapDB — registruje vsetky MapData resources podla ich `id` pola. Skenuje
# data/maps/ pri starte (autoload _ready()), rovnaky pattern ako CardDB.
# Buduci map-select / rotation / vote flow cita len z tohto dictionary —
# ziadne priame load()/preload() ciest po tomto bode.

const MAPS_PATH := "res://data/maps/"

var _maps: Dictionary = {} # StringName -> MapData

func _ready() -> void:
	_scan_into(MAPS_PATH, _maps)

func get_map(id: StringName) -> MapData:
	if not _maps.has(id):
		push_error("MapDB: unknown map id '%s'" % id)
		return null
	return _maps[id]

# Naskenovane ids — pre buducu map-select UI / rotaciu.
func list_map_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in _maps:
		ids.append(k)
	return ids

# TEMP: uniformny nahodny vyber, len pre PreMatchFlow testing (dalsi krok).
# Nahradi ho realna mode/rotation/vote logika neskor — rovnaky status ako
# PLAYER_HERO_ID/ENEMY_HERO_ID TEMP consty v arena.gd, nie je to teraz scoped.
func get_random_map_id() -> StringName:
	var ids := list_map_ids()
	if ids.is_empty():
		push_error("MapDB: ziadne mapy nenaskenovane, nedaju sa vybrat")
		return &""
	return ids[randi() % ids.size()]

func _scan_into(dir_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("MapDB: cannot open directory " + dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# export build listuje "*.tres.remap" namiesto "*.tres" — orezat
			# priponu skor nez sa zavola load()
			if file_name.ends_with(".remap"):
				file_name = file_name.substr(0, file_name.length() - len(".remap"))
			if file_name.ends_with(".tres"):
				_load_into(dir_path + file_name, target)
		file_name = dir.get_next()
	dir.list_dir_end()

func _load_into(path: String, target: Dictionary) -> void:
	var res := load(path)
	if res == null or not ("id" in res):
		push_error("MapDB: failed to load resource at " + path)
		return
	var res_id: StringName = res.id
	if target.has(res_id):
		push_error("MapDB: duplicate id '%s' (path %s)" % [res_id, path])
		return
	target[res_id] = res
