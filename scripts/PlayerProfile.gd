extends Node

# PlayerProfile — zbierka hraca (vlastnene karty a bohovia, kopie, levely)
# a balicky — JEDEN balicek (DECK_SIZE kariet) pre KAZDEHO boha + ktory boh
# je aktivny (ide do zapasu). Uklada sa do user://profile.json.
#
# JEDINE mutacne API: grant_cards(), set_deck(), upgrade_card(), reset_profile() a penazenka
# grant_currency(), try_spend_currency(), claim_daily_reward(), apply_wallet_snapshot()
# a ponuka kariet refresh_card_offers(), buy_card_offer() a relikviare (Rewards)
# update_reward_timers(), record_match_result(), grant_reliquary(), open_reliquary(). Neskor sa
# z nich stanu server volania — nikto iny NESMIE menit zbierku ani zostatky priamo.
# Lokalny save je cheatovatelny; pre testovanie je to v poriadku.
# Ziadne sceny/nody — rovnaky kontrakt ako EnergySystem.

signal profile_changed
# Zmena zostatku — LEN tento signal, nie profile_changed (Pantheon/Shop sa na
# profile_changed prestavuju, zmena zostatku ich nesmie spustit).
signal wallet_changed(currency: StringName, amount: int)
# Zmena ponuky kariet v Shope (refresh / kupa).
signal offers_changed
# Relikviare: fronta / free casovac / denny play progres. NIE profile_changed
# (grant_cards() pri otvoreni ho emituje sam ako doteraz).
signal rewards_changed

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 4
const DECK_SIZE := 7
# Ladiace cisla progresie (kopie na level, nasobice). Rovnaky resource ako
# BattleManager.LEVEL_CURVE — cisto data, ziadna scena.
const LEVEL_CURVE: LevelCurve = preload("res://data/progression/level_curve.tres")
# Rozsahy dennej odmeny (zatial tester faucet) — cisto data.
const DAILY_REWARD: DailyRewardData = preload("res://data/economy/daily_reward.tres")
# Ponuka kariet: pocet, vahy rarit, ceny — cisto data.
const CARD_OFFER_CHART: CardOfferChart = preload("res://data/economy/card_offers.tres")
# Zdroje relikviarov (FREE casovac, DAILY PLAY, VICTORY) — cisto data.
const REWARDS: RewardsConfig = preload("res://data/economy/rewards.tres")

# Starter grant — prvy start (alebo poskodeny/nekompatibilny save).
const STARTER_HERO: StringName = &"hero_zeus"
const STARTER_CARDS: Array[StringName] = [
	&"card_greek_hoplite", &"card_greek_toxotes", &"card_greek_peltast",
	&"card_greek_hippeus", &"card_greek_gastraphetes",
	&"card_greek_storm", &"card_greek_stun",
]

const CURRENCY_GOLD: StringName = &"gold"
const CURRENCY_CRYSTALS: StringName = &"crystals"
const CURRENCIES: Array[StringName] = [CURRENCY_GOLD, CURRENCY_CRYSTALS]
# Startovacia penazenka — novy profil, reset aj migracia starych saveov
const STARTER_WALLET := {&"gold": 500, &"crystals": 50}

# id -> {"level": int, "copies": int}. copies = duplikaty NAD prvy kus.
var _cards: Dictionary = {}
var _heroes: Dictionary = {}
# Balicek pre KAZDEHO boha: hero_id -> Array[StringName] (presne DECK_SIZE).
var _decks: Dictionary = {}
# Boh, s ktorym sa ide do zapasu. Jeho balicek je "aktivny".
var _active_hero: StringName = &""
# currency -> int (nikdy zaporne)
var _wallet: Dictionary = {}
# Ponuka kariet — LEN v pamati (session). Restart = nova ponuka. TODO(server): server drzi
# sadu aj kupene a vracia ju pri starte.
var _offers: Array = []   # [{ "id": StringName, "bought": bool }]
# Relikviare (Rewards)
var _reliquaries: Array[StringName] = []   # fronta pack id, FIFO
var _free_next_at: int = 0                 # unix s; 0 = pozastavene (zasoba plna)
var _play_day: String = ""                 # lokalny datum "YYYY-MM-DD"
var _play_count: int = 0
var _play_claimed: bool = false

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

# Neznama mena -> 0.
func get_currency(currency: StringName) -> int:
	return _wallet.get(currency, 0)

func can_afford(currency: StringName, amount: int) -> bool:
	return get_currency(currency) >= amount

# Ponuka kariet (hlboka kopia). Prazdna -> prvy hod (lenivo, bez offers_changed).
func get_card_offers() -> Array:
	if _offers.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_roll_offers(rng)
	return _offers.duplicate(true)

# {currency, price, copies} z CARD_OFFER_CHART podla rarity karty. Nie karta -> {}.
func get_offer_price(card_id: StringName) -> Dictionary:
	if not CardDB.has_card(card_id):
		push_warning("PlayerProfile: get_offer_price neznama karta '%s'" % card_id)
		return {}
	var rarity := CardDB.get_card(card_id).rarity
	return {
		"currency": CARD_OFFER_CHART.currency_for(rarity),
		"price": CARD_OFFER_CHART.price_for(rarity),
		"copies": CARD_OFFER_CHART.copies_for(rarity),
	}

# Fronta relikviarov (kopia), index 0 = najstarsi.
func get_reliquary_queue() -> Array[StringName]:
	return _reliquaries.duplicate()

# Sekundy do dalsieho free relikviara; -1 = pozastavene (zasoba plna).
func get_free_reliquary_seconds_left() -> int:
	if _free_next_at == 0:
		return -1
	return maxi(_free_next_at - _now(), 0)

# Kolko free relikviarov je vo fronte.
func get_free_reliquary_stock() -> int:
	return _reliquaries.count(REWARDS.free_pack_id)

# {count, goal, claimed}. Uvazuje novy den, ale NIC nemeni (to robi update_reward_timers).
func get_play_progress() -> Dictionary:
	var same_day := _play_day == Time.get_date_string_from_system()
	return {
		"count": _play_count if same_day else 0,
		"goal": REWARDS.play_goal,
		"claimed": _play_claimed if same_day else false,
	}

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
	_wallet = STARTER_WALLET.duplicate()
	_reset_rewards_state()
	save_profile()
	profile_changed.emit()
	for currency in CURRENCIES:
		wallet_changed.emit(currency, get_currency(currency))
	# prvy free relikviar hned (tester friendly) + rewards_changed
	update_reward_timers()

# --- Penazenka (mutacne API) ---
# Neskor sa z nich stanu server requesty, rovnako ako grant_cards().

func grant_currency(currency: StringName, amount: int, reason: String) -> void:
	if amount <= 0 or not CURRENCIES.has(currency):
		push_warning("PlayerProfile: grant_currency neplatne '%s' %d (%s) — preskakujem" % [currency, amount, reason])
		return
	_wallet[currency] = get_currency(currency) + amount
	save_profile()
	_emit_wallet(currency, amount, reason)

# false (a nic nezmeni) ak nestaci zostatok. amount <= 0 = zadarmo -> true.
func try_spend_currency(currency: StringName, amount: int, reason: String) -> bool:
	if amount <= 0:
		return true
	if not can_afford(currency, amount):
		return false
	_wallet[currency] = get_currency(currency) - amount
	save_profile()
	_emit_wallet(currency, -amount, reason)
	return true

# Denna odmena: hodi nahodne sumy a pripise ich. Vrati {gold: int, crystals: int}.
# SERVER SEAM: neskor JEDEN request claim_daily — server hodi kocky, overi limit a vrati
# sumy + novu penazenku (apply_wallet_snapshot). Klient sumy nikdy neposiela.
func claim_daily_reward(rng: RandomNumberGenerator) -> Dictionary:
	var gold := _roll_range(rng, DAILY_REWARD.gold_min, DAILY_REWARD.gold_max)
	var crystals := _roll_range(rng, DAILY_REWARD.crystals_min, DAILY_REWARD.crystals_max)
	var got := {CURRENCY_GOLD: gold, CURRENCY_CRYSTALS: crystals}
	for currency in got:
		_wallet[currency] = get_currency(currency) + got[currency]
	save_profile()
	for currency in got:
		if got[currency] > 0:
			_emit_wallet(currency, got[currency], "daily_reward")
	return got

# --- Ponuka kariet (mutacne API) ---

# TESTER: zadarmo a bez limitu. TODO(economy): cena (REFRESH NOW 500 gold) + casovac
func refresh_card_offers(rng: RandomNumberGenerator) -> void:
	_roll_offers(rng)
	offers_changed.emit()

# SERVER SEAM: neskor request buy_offer(index); server overi cenu, strhne, prida kopie,
# vrati novu penazenku + stav ponuky. Klient NIKDY neposiela cenu.
func buy_card_offer(index: int) -> bool:
	if index < 0 or index >= _offers.size() or _offers[index]["bought"]:
		return false
	var id: StringName = _offers[index]["id"]
	var price := get_offer_price(id)
	if price.is_empty():
		return false
	if not try_spend_currency(price["currency"], price["price"], "offer:%s" % id):
		return false
	var ids: Array[StringName] = []
	for i in price["copies"]:
		ids.append(id)
	grant_cards(ids)
	_offers[index]["bought"] = true
	offers_changed.emit()
	return true

# SERVER SEAM: server diktuje zostatky (pri starte / po odpovedi na nakup).
# Nahradi zostatky naraz: citaju sa len CURRENCIES kluce (String aj StringName),
# hodnoty int, zaporne/necislo -> 0. Chybajuci kluc necha sucasnu hodnotu.
func apply_wallet_snapshot(snapshot: Dictionary) -> void:
	var changed := false
	for currency in CURRENCIES:
		var raw: Variant = null
		if snapshot.has(currency):
			raw = snapshot[currency]
		elif snapshot.has(String(currency)):
			raw = snapshot[String(currency)]
		else:
			continue
		var value := 0
		if raw is int or raw is float:
			value = int(raw)
			if value < 0:
				push_warning("PlayerProfile: zaporny zostatok %s=%d — nastavujem 0" % [currency, value])
				value = 0
		else:
			push_warning("PlayerProfile: neplatny zostatok %s=%s — nastavujem 0" % [currency, raw])
		var old := get_currency(currency)
		if value == old and _wallet.has(currency):
			continue
		_wallet[currency] = value
		changed = true
		_emit_wallet(currency, value - old, "snapshot")
	if changed:
		save_profile()

# --- Relikviare (mutacne API) ---

# Dobehne FREE casovac (dobehnute intervaly sa doplnia az po zasobu) a novy den
# pre DAILY PLAY. Vola sa pri starte, pred kazdou rewards mutaciou a z UI (Rewards tab).
# SERVER SEAM: neskor stav casovaca a denneho progresu drzi server (jeho hodiny),
# klient len zobrazuje snapshot.
func update_reward_timers() -> void:
	var now := _now()
	var interval := _free_interval_s()
	var changed := false
	# hodiny posunute dozadu -> casovac znova od teraz
	if _free_next_at > 0 and _free_next_at - now > interval:
		_free_next_at = now + interval
		changed = true
	while get_free_reliquary_stock() < REWARDS.free_max_stock and _free_next_at > 0 and now >= _free_next_at:
		_enqueue(REWARDS.free_pack_id, "free_timer")
		_free_next_at += interval
		changed = true
	if get_free_reliquary_stock() >= REWARDS.free_max_stock:
		if _free_next_at != 0:
			_free_next_at = 0
			changed = true
	elif _free_next_at == 0:
		# samooprava: zasoba nie je plna, ale casovac stoji (rucne upraveny save)
		_free_next_at = now + interval
		changed = true
	var today := Time.get_date_string_from_system()
	if _play_day != today:
		_play_day = today
		_play_count = 0
		_play_claimed = false
		changed = true
	if changed:
		save_profile()
		rewards_changed.emit()

# Zapocita dohrany zapas (vyhra/prehra/remiza = +1 DAILY PLAY), vyhra prida VICTORY.
# Vrati pridane relikviare.
# SERVER SEAM: neskor server zapise vysledok sam z autoritativneho zapasu — klient
# vysledok NIKDY neposiela; toto len prijme zoznam pridanych relikviarov.
func record_match_result(winner: String) -> Array[StringName]:
	update_reward_timers()
	var added: Array[StringName] = []
	_play_count = mini(_play_count + 1, REWARDS.play_goal)
	if _play_count >= REWARDS.play_goal and not _play_claimed:
		_enqueue(REWARDS.play_pack_id, "daily_play")
		added.append(REWARDS.play_pack_id)
		_play_claimed = true
	if winner == "player":
		_enqueue(REWARDS.victory_pack_id, "victory")
		added.append(REWARDS.victory_pack_id)
	DebugLog.info("rewards", "match %s -> play %d/%d" % [winner, _play_count, REWARDS.play_goal])
	save_profile()
	rewards_changed.emit()
	return added

# Prida relikviar do fronty (eventy / mail neskor; debug). Len shop_visible == false packy.
# SERVER SEAM: neskor ho prida len server (event/mail), klient dostane novu frontu.
func grant_reliquary(pack_id: StringName) -> void:
	if not _is_known_pack(pack_id):
		push_error("PlayerProfile: grant_reliquary neznamy pack '%s'" % pack_id)
		return
	if CardDB.get_pack(pack_id).shop_visible:
		push_error("PlayerProfile: grant_reliquary '%s' nie je relikviar (shop_visible)" % pack_id)
		return
	update_reward_timers()
	_enqueue(pack_id, "grant")
	save_profile()
	rewards_changed.emit()

# Otvori relikviar na indexe fronty: vyberie ho, zrolluje a pripise karty.
# Vrati {"pack_id": StringName, "cards": Array[StringName], "is_new": Array[bool]};
# neplatny index -> {}.
# SERVER SEAM: neskor request open_reliquary(index) — server overi frontu, zrolluje
# a vrati karty + novu frontu. Klient nikdy neposiela vysledok hodu.
func open_reliquary(index: int, rng: RandomNumberGenerator) -> Dictionary:
	update_reward_timers()
	if index < 0 or index >= _reliquaries.size():
		return {}
	var pack_id: StringName = _reliquaries[index]
	_reliquaries.remove_at(index)
	if pack_id == REWARDS.free_pack_id and _free_next_at == 0:
		# zasoba uz nie je plna -> casovac znova bezi
		_free_next_at = _now() + _free_interval_s()
	if not _is_known_pack(pack_id):
		push_warning("PlayerProfile: relikviar '%s' uz neexistuje — zahadzujem" % pack_id)
		save_profile()
		rewards_changed.emit()
		return {}
	var pack := CardDB.get_pack(pack_id)
	var rolled := PackRoller.roll(pack, rng, CardDB.get_pack_pool(pack.faction))

	# NEW sa urcuje PRED grantom; id padnute 2x v jednom balicku je NEW len prvy raz
	var is_new: Array[bool] = []
	var seen := {}
	for id in rolled:
		var owned := owns_card(id) or owns_hero(id)
		is_new.append(not owned and not seen.has(id))
		seen[id] = true

	grant_cards(rolled)
	DebugLog.info("rewards", "open %s -> %s, queue=%s" % [pack_id, rolled, _reliquaries])
	save_profile()
	rewards_changed.emit()
	return {"pack_id": pack_id, "cards": rolled, "is_new": is_new}

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
	var wallet_out := {}
	for currency in CURRENCIES:
		wallet_out[String(currency)] = get_currency(currency)
	var queue_out: Array[String] = []
	for id in _reliquaries:
		queue_out.append(String(id))
	var rewards_out := {
		"queue": queue_out,
		"free_next_at": _free_next_at,
		"play_day": _play_day,
		"play_count": _play_count,
		"play_claimed": _play_claimed,
	}
	var data := {
		"save_version": SAVE_VERSION,
		"cards": cards_out,
		"heroes": heroes_out,
		"active_hero": String(_active_hero),
		"decks": decks_out,
		"wallet": wallet_out,
		"rewards": rewards_out,
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
	# cisty zaklad, na ktory sa aplikuje snapshot zo savu
	_wallet.clear()
	for currency in CURRENCIES:
		_wallet[currency] = 0
	_reset_rewards_state()

	if not FileAccess.file_exists(SAVE_PATH):
		# prvy start
		_apply_starter()
		_wallet = STARTER_WALLET.duplicate()
		save_profile()
		update_reward_timers()
		_check_content()
		_print_summary()
		return

	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var version := int(parsed.get("save_version", -1)) if parsed is Dictionary else -1
	if version < 1 or version > SAVE_VERSION:
		push_warning("PlayerProfile: poskodeny alebo nekompatibilny save — obnovujem starter profil")
		_apply_starter()
		_wallet = STARTER_WALLET.duplicate()
		save_profile()
		update_reward_timers()
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
		DebugLog.info("profile", "migrated save v1 -> v2")
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

	# Penazenka: v1/v2 ju nemali -> starter. Zle hodnoty orezava apply_wallet_snapshot,
	# profil sa kvoli zlej penazenke NEresetuje.
	var saved_wallet: Dictionary = {}
	if version < 3:
		saved_wallet = STARTER_WALLET.duplicate()
		DebugLog.info("profile", "migrated save v%d -> v3" % version)
		needs_save = true
	else:
		var wallet_raw: Variant = parsed.get("wallet")
		if wallet_raw is Dictionary:
			saved_wallet = wallet_raw
		else:
			push_warning("PlayerProfile: save nema platnu penazenku — zostatky 0")
	_sync_wallet_at_start(saved_wallet)

	# Relikviare: v1..v3 ich nemali -> prazdna fronta, prvy free hned (_reset_rewards_state hore).
	if version < 4:
		DebugLog.info("profile", "migrated save v%d -> v4" % version)
		needs_save = true
	else:
		_read_rewards(parsed.get("rewards"))

	if needs_save:
		save_profile()
	update_reward_timers()
	_check_content()
	_print_summary()

# v4 "rewards" blok. Zle typy -> predvolene hodnoty; nezname pack id z fronty von.
func _read_rewards(raw: Variant) -> void:
	if not (raw is Dictionary):
		push_warning("PlayerProfile: save nema platny rewards blok — predvolene hodnoty")
		return
	_reliquaries.clear()
	for pack_id in _read_id_list(raw.get("queue")):
		if _is_known_pack(pack_id):
			_reliquaries.append(pack_id)
		else:
			push_warning("PlayerProfile: neznamy relikviar '%s' v save — zahadzujem" % pack_id)
	var next_raw: Variant = raw.get("free_next_at")
	if next_raw is int or next_raw is float:
		_free_next_at = maxi(int(next_raw), 0)
	var day_raw: Variant = raw.get("play_day")
	if day_raw is String:
		_play_day = day_raw
	var count_raw: Variant = raw.get("play_count")
	if count_raw is int or count_raw is float:
		_play_count = clampi(int(count_raw), 0, REWARDS.play_goal)
	var claimed_raw: Variant = raw.get("play_claimed")
	if claimed_raw is bool:
		_play_claimed = claimed_raw

# TODO(server): pri starte server posle penazenku; zatial je "server" lokalny save.
# Sietovy fetch nahradi len tuto funkciu.
func _sync_wallet_at_start(saved_wallet: Dictionary) -> void:
	apply_wallet_snapshot(saved_wallet)

# --- Interne ---

func _now() -> int:
	return int(Time.get_unix_time_from_system())

func _free_interval_s() -> int:
	return maxi(int(REWARDS.free_interval_hours * 3600.0), 1)

# CardDB nema has_pack a get_pack() na nezname id hlasi push_error.
func _is_known_pack(pack_id: StringName) -> bool:
	return CardDB.list_pack_ids().has(pack_id)

func _enqueue(pack_id: StringName, reason: String) -> void:
	_reliquaries.append(pack_id)
	DebugLog.info("rewards", "%s +%s -> queue=%s" % [reason, pack_id, _reliquaries])

# Prazdna fronta, prvy free relikviar hned (_free_next_at = teraz), play progres od nuly.
# Novy profil, reset, poskodeny save aj migracia v1..v3.
func _reset_rewards_state() -> void:
	_reliquaries.clear()
	_free_next_at = _now()
	_play_day = ""
	_play_count = 0
	_play_claimed = false

func _emit_wallet(currency: StringName, delta: int, reason: String) -> void:
	var balance := get_currency(currency)
	DebugLog.info("wallet", "%s: %s %+d -> %d" % [reason, currency, delta, balance])
	wallet_changed.emit(currency, balance)

# Nova ponuka: vsetky karty z packov (kazdy panteon, vlastnene aj zamknute), bez bohov.
func _roll_offers(rng: RandomNumberGenerator) -> void:
	var pool: Dictionary = {}
	var raw := CardDB.get_pack_pool(&"")
	for rarity in raw:
		if rarity == 4:
			continue
		var ids: Array = []
		for id in raw[rarity]:
			if CardDB.has_card(id):
				ids.append(id)
		if not ids.is_empty():
			pool[rarity] = ids
	_offers.clear()
	for id in OfferRoller.roll(CARD_OFFER_CHART, rng, pool):
		_offers.append({"id": id, "bought": false})

# Nahodne cislo z <a, b>; zaporne -> 0, max < min sa prehodi.
func _roll_range(rng: RandomNumberGenerator, a: int, b: int) -> int:
	var lo := maxi(a, 0)
	var hi := maxi(b, 0)
	if hi < lo:
		var tmp := lo
		lo = hi
		hi = tmp
	return rng.randi_range(lo, hi)

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
	DebugLog.info("profile", "active_hero=%s deck=%s saved_decks=%d owned_cards=%d owned_heroes=%d" % [
		_active_hero, get_deck_cards(), _decks.size(), _cards.size(), _heroes.size()])
	DebugLog.info("profile", "wallet gold=%d crystals=%d" % [
		get_currency(CURRENCY_GOLD), get_currency(CURRENCY_CRYSTALS)])
	DebugLog.info("rewards", "queue=%s free_in=%ds play=%s" % [
		_reliquaries, get_free_reliquary_seconds_left(), get_play_progress()])
