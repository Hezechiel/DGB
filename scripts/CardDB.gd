extends Node

# CardDB — registruje vsetky CardData a UnitData resources podla ich `id`
# polia. Skenuje data/cards/ a data/units/ pri starte (autoload _ready()).
# Buduci network handler a drag-to-deploy citaju len z tychto dictionaries —
# ziadne priame load()/preload() ciest po tomto bode.

const CARDS_PATH := "res://data/cards/"
const UNITS_PATH := "res://data/units/"
const HEROES_PATH := "res://data/heroes/"
const SPELLS_PATH := "res://data/spells/"

var _cards: Dictionary = {} # StringName -> CardData
var _units: Dictionary = {} # StringName -> UnitData
var _heroes: Dictionary = {} # StringName -> HeroData
var _spells: Dictionary = {} # StringName -> SpellData

func _ready() -> void:
	_scan_into(CARDS_PATH, _cards)
	_scan_into(UNITS_PATH, _units)
	_scan_into(HEROES_PATH, _heroes)
	_scan_into(SPELLS_PATH, _spells)

func get_card(id: StringName) -> CardData:
	if not _cards.has(id):
		push_error("CardDB: unknown card id '%s'" % id)
		return null
	return _cards[id]

func get_unit(id: StringName) -> UnitData:
	if not _units.has(id):
		push_error("CardDB: unknown unit id '%s'" % id)
		return null
	return _units[id]

func get_hero(id: StringName) -> HeroData:
	if not _heroes.has(id):
		push_error("CardDB: unknown hero id '%s'" % id)
		return null
	return _heroes[id]

func get_spell(id: StringName) -> SpellData:
	if not _spells.has(id):
		push_error("CardDB: unknown spell id '%s'" % id)
		return null
	return _spells[id]

func _scan_into(dir_path: String, target: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("CardDB: cannot open directory " + dir_path)
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
		push_error("CardDB: failed to load resource at " + path)
		return
	# Karta musi mat PRAVE JEDEN payload — unit alebo spell. Guard len pre
	# CardData; UnitData/HeroData/SpellData tuto vazbu nemaju.
	if res is CardData:
		var has_unit: bool = res.unit_data != null
		var has_spell: bool = res.spell_data != null
		if has_unit == has_spell:
			push_error("CardDB: card at %s musi mat prave jedno z unit_data/spell_data" % path)
			return
	var res_id: StringName = res.id
	if target.has(res_id):
		push_error("CardDB: duplicate id '%s' (path %s)" % [res_id, path])
		return
	target[res_id] = res
