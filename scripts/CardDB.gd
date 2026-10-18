extends Node

# CardDB — registruje karty (UnitData / SpellData, obe su CardData),
# HeroData a PackData resources podla ich `id` polia. Skenuje SCAN_ROOTS REKURZIVNE pri
# starte (autoload _ready()); priecinky "frames" a "skills" preskakuje.
# Resource sa zaradi podla TYPU, nie podla priecinka — rozlozenie suborov
# (napr. cards/greek/units/, Oct 2026) sa tak moze menit bez zmeny kodu.
# Chybajuci koren sa ticho preskoci. Z kariet a bohov s obtain_source == 1
# sklada drop pool pre PackRoller.
# Resources are routed by type, not folder, so the layout can change freely.
# Buduci network handler a drag-to-deploy citaju len z tychto dictionaries —
# ziadne priame load()/preload() ciest po tomto bode.

# units/ a spells/ su stare korene (pred presunom pod cards/<pantheon>/) —
# ak uz neexistuju, preskocia sa. / Legacy roots, skipped once gone.
const SCAN_ROOTS := [
	"res://data/cards/",
	"res://data/heroes/",
	"res://data/packs/",
	"res://data/units/",
	"res://data/spells/",
]
# Podpriecinky bez CardDB obsahu: SpriteFrames (bez `id`) a SkillData boha
# (dosiahnute cez HeroData.skill). / Folders CardDB never loads.
const SKIP_DIRS := ["frames", "skills"]

var _cards: Dictionary = {} # StringName -> CardData (UnitData / SpellData)
var _heroes: Dictionary = {} # StringName -> HeroData
var _packs: Dictionary = {} # StringName -> PackData

func _ready() -> void:
	for root in SCAN_ROOTS:
		if DirAccess.dir_exists_absolute(root):
			_scan_dir(root)

func get_card(id: StringName) -> CardData:
	if not _cards.has(id):
		push_error("CardDB: unknown card id '%s'" % id)
		return null
	return _cards[id]

func get_hero(id: StringName) -> HeroData:
	if not _heroes.has(id):
		push_error("CardDB: unknown hero id '%s'" % id)
		return null
	return _heroes[id]

func get_pack(id: StringName) -> PackData:
	if not _packs.has(id):
		push_error("CardDB: unknown pack id '%s'" % id)
		return null
	return _packs[id]

# Zoradene (deterministicke poradie nezavisle od poradia suborov na disku).
func list_pack_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_packs.keys())
	ids.sort()
	return ids

# Zoradene id-cka — deterministicke poradie pre UI zoznamy.
func list_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_cards.keys())
	ids.sort()
	return ids

func list_hero_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_heroes.keys())
	ids.sort()
	return ids

# Drop pool pre PackRoller: rarity kod -> ZORADENE pole id-ciek. Obsahuje
# karty AJ bohov s obtain_source == 1 (PACK). faction &"" = bez filtra.
func get_pack_pool(faction: StringName) -> Dictionary:
	var pool: Dictionary = {}
	for source in [_cards, _heroes]:
		for id in source:
			var res = source[id]
			if res.obtain_source != 1:
				continue
			if faction != &"" and res.faction != faction:
				continue
			if not pool.has(res.rarity):
				pool[res.rarity] = []
			pool[res.rarity].append(id)
	for rarity in pool:
		pool[rarity].sort()
	return pool

# Tiche overenie existencie — get_card()/get_hero() pri neznamom id
# push_error-uju, co sa nehodi pri validacii ulozeneho profilu.
func has_card(id: StringName) -> bool:
	return _cards.has(id)

func has_hero(id: StringName) -> bool:
	return _heroes.has(id)

func _scan_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("CardDB: cannot open directory " + dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			# rekurzia do podpriecinkov (napr. cards/greek/units/)
			if file_name not in SKIP_DIRS and not file_name.begins_with("."):
				_scan_dir(dir_path + file_name + "/")
		else:
			# export build listuje "*.tres.remap" namiesto "*.tres" — orezat
			# priponu skor nez sa zavola load()
			if file_name.ends_with(".remap"):
				file_name = file_name.substr(0, file_name.length() - len(".remap"))
			if file_name.ends_with(".tres"):
				_load_resource(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

# Zaradi resource do slovnika podla typu. / Routes a resource by its type.
func _load_resource(path: String) -> void:
	var res := load(path)
	if res == null or not ("id" in res):
		push_error("CardDB: failed to load resource at " + path)
		return
	var target: Dictionary
	if res is UnitData or res is SpellData:
		target = _cards
	elif res is CardData:
		# holy CardData je len zaklad — stara karta pred zlucenim (Oct 2026)
		push_error("CardDB: %s je holy CardData (stary format karty) — zmaz ho" % path)
		return
	elif res is HeroData:
		target = _heroes
	elif res is PackData:
		target = _packs
	else:
		push_error("CardDB: neznamy typ resource v %s" % path)
		return
	var res_id: StringName = res.id
	if target.has(res_id):
		push_error("CardDB: duplicate id '%s' (path %s)" % [res_id, path])
		return
	target[res_id] = res
