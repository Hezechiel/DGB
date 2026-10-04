extends Node

# PlayerProfile — zbierka hraca (vlastnene karty a bohovia, kopie, levely)
# a balicky — JEDEN balicek (DECK_SIZE kariet) pre KAZDEHO boha + ktory boh
# je aktivny (ide do zapasu). Uklada sa do user://profile.json.
#
# JEDINE mutacne API: grant_cards(), set_deck(), upgrade_card(), reset_profile(). Neskor sa
# z nich stanu server volania — nikto iny NESMIE menit zbierku priamo.
# Lokalny save je cheatovatelny; pre testovanie je to v poriadku.
# Ziadne sceny/nody — rovnaky kontrakt ako EnergySystem.

signal profile_changed

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 2
const DECK_SIZE := 7
# Ladiace cisla progresie (kopie na level, nasobice). Rovnaky resource ako
# BattleManager.LEVEL_CURVE — cisto data, ziadna scena.
const LEVEL_CURVE: LevelCurve = preload("res://data/progression/level_curve.tres")

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
# Balicek pre KAZDEHO boha: hero_id -> Array[StringName] (presne DECK_SIZE).
var _decks: Dictionary = {}
# Boh, s ktorym sa ide do zapasu. Jeho balicek je "aktivny".
var _active_hero: StringName = &""

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

# Kolko kopii treba na dalsi level. -1 = nevlastnene, neznamy id alebo max level.
func get_copies_to_next(id: StringName) -> int:
	if CardDB.has_card(id) and _cards.has(id):
		return LEVEL_CURVE.copies_to_next(CardDB.get_card(id).rarity, _cards[id]["level"])
	if CardDB.has_hero(id) and _heroes.has(id):
		return LEVEL_CURVE.copies_to_next(CardDB.get_hero(id).rarity, _heroes[id]["level"])
	return -1

func can_upgrade(id: StringName) -> bool:
	var need := get_copies_to_next(id)
	if need < 0:
		return false
	var copies: int = get_card_copies(id) if _cards.has(id) else get_hero_copies(id)
	return copies >= need

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
	return _active_hero

func get_deck_cards() -> Array[StringName]:
	var cards: Array[StringName] = []
	if _decks.has(_active_hero):
		cards.assign(_decks[_active_hero])
	return cards

func has_saved_deck(hero_id: StringName) -> bool:
	return _decks.has(hero_id)

# Ulozeny balicek boha (kopia), inak predvoleny z DeckRules: aktivny balicek
# s odmietnutymi kartami nahradenymi vlastnenymi (cost, potom id).
# NIC neuklada. Neznamy boh -> prazdne pole.
func get_deck_for(hero_id: StringName) -> Array[StringName]:
	var cards: Array[StringName] = []
	if _decks.has(hero_id):
		cards.assign(_decks[hero_id])
		return cards
	if not CardDB.has_hero(hero_id):
		return cards
	var base := _card_datas(get_deck_cards())
	var owned_ids := get_owned_card_ids()
	owned_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var cost_a := CardDB.get_card(a).cost
		var cost_b := CardDB.get_card(b).cost
		if cost_a != cost_b:
			return cost_a < cost_b
		return a < b
	)
	var pool := _card_datas(owned_ids)
	return DeckRules.build_default_deck(CardDB.get_hero(hero_id), base, pool, DECK_SIZE)

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
	var cards: Array[StringName] = []
	cards.assign(card_ids)
	_decks[hero_id] = cards
	_active_hero = hero_id
	save_profile()
	profile_changed.emit()
	return true

# Manualny level up: minie kopie a zdvihne level o 1. Jedine miesto, kde sa
# level meni. Vrati false (a nic nezmeni), ak sa upgradovat neda.
func upgrade_card(id: StringName) -> bool:
	if not can_upgrade(id):
		return false
	var need := get_copies_to_next(id)
	var entry: Dictionary = _cards[id] if _cards.has(id) else _heroes[id]
	entry["copies"] -= need
	entry["level"] += 1
	save_profile()
	profile_changed.emit()
	return true

func reset_profile() -> void:
	_cards.clear()
	_heroes.clear()
	_decks.clear()
	_active_hero = &""
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
	var decks_out := {}
	for hero_id in _decks:
		var ids_out: Array[String] = []
		for id in _decks[hero_id]:
			ids_out.append(String(id))
		decks_out[String(hero_id)] = ids_out
	var data := {
		"save_version": SAVE_VERSION,
		"cards": cards_out,
		"heroes": heroes_out,
		"active_hero": String(_active_hero),
		"decks": decks_out,
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
	_decks.clear()
	_active_hero = &""

	if not FileAccess.file_exists(SAVE_PATH):
		# prvy start
		_apply_starter()
		save_profile()
		_check_content()
		_print_summary()
		return

	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var version := int(parsed.get("save_version", -1)) if parsed is Dictionary else -1
	if version != 1 and version != SAVE_VERSION:
		push_warning("PlayerProfile: poskodeny alebo nekompatibilny save — obnovujem starter profil")
		_apply_starter()
		save_profile()
		_check_content()
		_print_summary()
		return

	_read_owned(parsed.get("cards"), _cards, true)
	_read_owned(parsed.get("heroes"), _heroes, false)

	var needs_save := false
	if version == 1:
		# v1 mal jediny balicek {"hero", "cards"} -> decks = {hero: cards}
		var deck: Variant = parsed.get("deck")
		if deck is Dictionary and deck.get("hero") is String:
			var hero_id := StringName(deck.get("hero"))
			_decks[hero_id] = _read_id_list(deck.get("cards"))
			_active_hero = hero_id
		print("[profile] migrated save v1 -> v2")
		needs_save = true
	else:
		var active_raw: Variant = parsed.get("active_hero")
		if active_raw is String:
			_active_hero = StringName(active_raw)
		var decks_raw: Variant = parsed.get("decks")
		if decks_raw is Dictionary:
			for key in decks_raw:
				_decks[StringName(str(key))] = _read_id_list(decks_raw[key])

	# neplatne balicky (nevlastneny boh/karta, zla velkost, odmietnuta karta) von
	for hero_id in _decks.keys():
		if not _is_deck_valid(hero_id, _decks[hero_id]):
			push_warning("PlayerProfile: ulozeny balicek boha '%s' je neplatny — zahadzujem" % hero_id)
			_decks.erase(hero_id)
			needs_save = true

	if not _heroes.has(_active_hero) or not _decks.has(_active_hero):
		push_warning("PlayerProfile: aktivny boh nema platny balicek — navrat na starter balicek")
		_apply_starter(true)
		needs_save = true

	if needs_save:
		save_profile()
	_check_content()
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
	var cards: Array[StringName] = []
	cards.assign(STARTER_CARDS)
	_decks[STARTER_HERO] = cards
	_active_hero = STARTER_HERO

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
	# boh proti karte (DeckRules) — plati aj pri nacitani savu
	return DeckRules.find_forbidden(CardDB.get_hero(hero_id), _card_datas(card_ids)).is_empty()

# Id-cka -> CardData (nezname id preskoci).
func _card_datas(ids: Array[StringName]) -> Array[CardData]:
	var result: Array[CardData] = []
	for id in ids:
		if CardDB.has_card(id):
			result.append(CardDB.get_card(id))
	return result

# JSON pole stringov -> Array[StringName]; ine typy sa ticho preskocia.
func _read_id_list(raw: Variant) -> Array[StringName]:
	var ids: Array[StringName] = []
	if raw is Array:
		for c in raw:
			if c is String:
				ids.append(StringName(c))
	return ids

# Kontrola obsahu: kazdy boh musi mat aspon DECK_SIZE povolenych kariet
# (obtain_source != 0). Len hlasi, nic nemeni.
func _check_content() -> void:
	for hero_id in CardDB.list_hero_ids():
		var hero := CardDB.get_hero(hero_id)
		var allowed := 0
		for card_id in CardDB.list_card_ids():
			var card := CardDB.get_card(card_id)
			if card.obtain_source != 0 and DeckRules.is_card_allowed(hero, card):
				allowed += 1
		if allowed < DECK_SIZE:
			push_error("PlayerProfile: OBSAH — boh '%s' ma len %d povolenych kariet (treba %d)" % [hero_id, allowed, DECK_SIZE])

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
	print("[profile] active_hero=%s deck=%s saved_decks=%d owned_cards=%d owned_heroes=%d" % [
		_active_hero, get_deck_cards(), _decks.size(), _cards.size(), _heroes.size()])
