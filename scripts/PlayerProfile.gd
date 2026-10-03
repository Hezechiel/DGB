extends Node

# PlayerProfile — zbierka hraca (vlastnene karty a bohovia, kopie, levely)
# a balicek (1 boh + DECK_SIZE kariet). Uklada sa do user://profile.json.
#
# JEDINE mutacne API: grant_cards(), set_deck(), reset_profile(). Neskor sa
# z nich stanu server volania — nikto iny NESMIE menit zbierku priamo.
# Lokalny save je cheatovatelny; pre testovanie je to v poriadku.
# Ziadne sceny/nody — rovnaky kontrakt ako EnergySystem.

signal profile_changed

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 1
const DECK_SIZE := 7

# Starter grant — prvy start (alebo poskodeny/nekompatibilny save).
const STARTER_HERO: StringName = &"hero_zeus"
const STARTER_CARDS: Array[StringName] = [
	&"card_greek_hoplite", &"card_greek_toxotes", &"card_greek_peltast",
	&"card_greek_hippeus", &"card_greek_gastraphetes",
	&"card_greek_storm", &"card_greek_stun",
]

# id -> {"level": int, "copies": int}. copies = duplikaty NAD prvy kus.
var _cards: Dictionary = {}
var _heroes: Dictionary = {}
var _deck_hero: StringName = &""
var _deck_cards: Array[StringName] = []

func _ready() -> void:
	load_profile()

# --- Read API (vsetko vracia kopie, nikdy interne kontajnery) ---

func owns_card(id: StringName) -> bool:
	return _cards.has(id)

func owns_hero(id: StringName) -> bool:
	return _heroes.has(id)

func get_card_level(id: StringName) -> int:
	return _cards[id]["level"] if _cards.has(id) else 0

func get_hero_level(id: StringName) -> int:
	return _heroes[id]["level"] if _heroes.has(id) else 0

func get_card_copies(id: StringName) -> int:
	return _cards[id]["copies"] if _cards.has(id) else 0

func get_hero_copies(id: StringName) -> int:
	return _heroes[id]["copies"] if _heroes.has(id) else 0

func get_owned_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _cards:
		ids.append(id)
	return ids

func get_owned_hero_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _heroes:
		ids.append(id)
	return ids

func get_deck_hero() -> StringName:
	return _deck_hero

func get_deck_cards() -> Array[StringName]:
	return _deck_cards.duplicate()

# --- Mutacne API ---

func grant_cards(ids: Array[StringName]) -> void:
	for id in ids:
		if CardDB.has_card(id):
			_grant_one(_cards, id)
		elif CardDB.has_hero(id):
			_grant_one(_heroes, id)
		else:
			push_warning("PlayerProfile: grant_cards neznamy id '%s' — preskakujem" % id)
	save_profile()
	profile_changed.emit()

func set_deck(hero_id: StringName, card_ids: Array[StringName]) -> bool:
	if not _is_deck_valid(hero_id, card_ids):
		return false
	_deck_hero = hero_id
	_deck_cards = card_ids.duplicate()
	save_profile()
	profile_changed.emit()
	return true

func reset_profile() -> void:
	_cards.clear()
	_heroes.clear()
	_deck_hero = &""
	_deck_cards.clear()
	_apply_starter()
	save_profile()
	profile_changed.emit()

# --- Persistencia ---

func save_profile() -> void:
	var cards_out := {}
	for id in _cards:
		cards_out[String(id)] = {"level": _cards[id]["level"], "copies": _cards[id]["copies"]}
	var heroes_out := {}
	for id in _heroes:
		heroes_out[String(id)] = {"level": _heroes[id]["level"], "copies": _heroes[id]["copies"]}
	var deck_cards_out: Array[String] = []
	for id in _deck_cards:
		deck_cards_out.append(String(id))
	var data := {
		"save_version": SAVE_VERSION,
		"cards": cards_out,
		"heroes": heroes_out,
		"deck": {"hero": String(_deck_hero), "cards": deck_cards_out},
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("PlayerProfile: nemozem zapisat %s (%s)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func load_profile() -> void:
	_cards.clear()
	_heroes.clear()
	_deck_hero = &""
	_deck_cards.clear()

	if not FileAccess.file_exists(SAVE_PATH):
		# prvy start
		_apply_starter()
		save_profile()
		_print_summary()
		return

	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or int(parsed.get("save_version", -1)) != SAVE_VERSION:
		push_warning("PlayerProfile: poskodeny alebo nekompatibilny save — obnovujem starter profil")
		_apply_starter()
		save_profile()
		_print_summary()
		return

	_read_owned(parsed.get("cards"), _cards, true)
	_read_owned(parsed.get("heroes"), _heroes, false)

	var deck: Variant = parsed.get("deck")
	if deck is Dictionary:
		var hero_raw: Variant = deck.get("hero")
		if hero_raw is String:
			_deck_hero = StringName(hero_raw)
		var cards_raw: Variant = deck.get("cards")
		if cards_raw is Array:
			for c in cards_raw:
				if c is String:
					_deck_cards.append(StringName(c))

	if not _is_deck_valid(_deck_hero, _deck_cards):
		push_warning("PlayerProfile: ulozeny balicek je neplatny — navrat na starter balicek")
		_apply_starter(true)
		save_profile()

	_print_summary()

# --- Interne ---

func _grant_one(target: Dictionary, id: StringName) -> void:
	if target.has(id):
		target[id]["copies"] += 1
	else:
		target[id] = {"level": 1, "copies": 0}

# only_missing = true: udeli len to co hrac este nema, NIKDY nepridava kopie
# (oprava neplatneho balicka nesmie byt zdroj duplikatov).
func _apply_starter(only_missing: bool = false) -> void:
	if not (only_missing and _heroes.has(STARTER_HERO)):
		_grant_one(_heroes, STARTER_HERO)
	for id in STARTER_CARDS:
		if not (only_missing and _cards.has(id)):
			_grant_one(_cards, id)
	_deck_hero = STARTER_HERO
	_deck_cards = STARTER_CARDS.duplicate()

func _is_deck_valid(hero_id: StringName, card_ids: Array[StringName]) -> bool:
	if not _heroes.has(hero_id):
		return false
	if card_ids.size() != DECK_SIZE:
		return false
	var seen := {}
	for id in card_ids:
		if not _cards.has(id) or seen.has(id):
			return false
		seen[id] = true
	return true

# JSON cisla prichadzaju ako float -> int(). Id ktore CardDB uz nepozna
# (premenovany/zmazany obsah) sa ticho zahodia s jednym warningom.
func _read_owned(raw: Variant, target: Dictionary, is_card: bool) -> void:
	if not (raw is Dictionary):
		return
	for key in raw:
		var id := StringName(str(key))
		var known := CardDB.has_card(id) if is_card else CardDB.has_hero(id)
		if not known:
			push_warning("PlayerProfile: neznamy id '%s' v save — zahadzujem" % id)
			continue
		var entry: Variant = raw[key]
		var level := 1
		var copies := 0
		if entry is Dictionary:
			level = int(entry.get("level", 1))
			copies = int(entry.get("copies", 0))
		target[id] = {"level": maxi(level, 1), "copies": maxi(copies, 0)}

func _print_summary() -> void:
	print("[profile] hero=%s deck=%s owned_cards=%d owned_heroes=%d" % [
		_deck_hero, _deck_cards, _cards.size(), _heroes.size()])
