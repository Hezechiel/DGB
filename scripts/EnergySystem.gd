extends Node

# Energia zapasu — per-team stav + matematika. ZAMERNE samostatny autoload,
# nie sucast BattleManageru.
#
# TVRDE PRAVIDLO: tento subor NESMIE poznat sceny, nody, UI ani arena_root.
# Ziadny preload() sceny, ziadny instantiate(), ziadny add_child(), ziadna
# referencia na Node. Ciste stav + matematika — na autoritativnom serveri musi
# bezat presne tato logika 1:1. BattleManager tento test nesplna (drzi
# arena_root, preloaduje player.tscn, vola instantiate()), preto energia
# nezije v nom.
#
# Jedina povolena zavislost je CardDB (cena karty). CardDB je rovnako
# server-side koncept — bakovana DB, verzia sa kontroluje pri matchmakingu
# (architecture.md §7). NEPRIDAVAJ sem referenciu na BattleManager:
# start()/stop()/reset_match_state() riadi volajuci (dnes arena.gd, neskor
# serverova match slucka).

signal energy_int_changed(team: String, value: int)

const MAX_ENERGY := 10.0
const START_ENERGY := 7.0
const BASE_REGEN_PER_SEC := 0.25   # 1 energia / 4 s
const INFINITE_DURATION := -1.0    # modifikator bez expiracie (rusi sa cez remove_modifier)
const TEAMS: Array[String] = ["player", "enemy"]

# COST_REFUND (vratenie casti ceny PO zaplateni, s RNG procom) zatial ZAMERNE
# chyba — ability nie je doriesena. Enum existuje prave preto, aby sa dal
# pridat bez prepisovania zvysku.
enum ModType {
	REGEN_MULT,    # value = nasobic regeneracie (2.0 = dvojnasobna)
	COST_REDUCE,   # value = kolko energie sa odpocita z ceny karty (bloodlust)
}

var _energy: Dictionary = {}     # team -> float
var _last_int: Dictionary = {}   # team -> int, na detekciu prechodu celeho cisla
var _modifiers: Dictionary = {}  # team -> Array[Dictionary]
var _running: bool = false

func _ready() -> void:
	reset_match_state()   # aby get_energy() fungovalo aj pred prvym zapasom

# Volane z arena._enter_tree(). POZOR: EnergySystem NIE JE sucastou
# BattleManager.reset_match_state() — je to samostatny autoload, takze kazdy
# novy per-match stav TU sa musi resetovat TU. Rovnaka pastca ako
# architecture.md §6 popisuje pre BattleManager, len druhy autoload.
func reset_match_state() -> void:
	_running = false
	_energy.clear(); _last_int.clear(); _modifiers.clear()
	for team in TEAMS:
		_energy[team] = START_ENERGY
		_last_int[team] = floori(START_ENERGY)
		_modifiers[team] = []

func start() -> void:
	_running = true

func stop() -> void:
	_running = false

func is_running() -> bool:
	return _running

func get_energy(team: String) -> float:
	return _energy.get(team, 0.0)

func get_energy_int(team: String) -> int:
	return floori(get_energy(team))

func get_max_energy() -> int:
	return int(MAX_ENERGY)

# Vsetky REGEN_MULT sa NASOBIA (stackuju) — rozhodnute, nie bug.
func get_regen_rate(team: String) -> float:
	var rate := BASE_REGEN_PER_SEC
	for m in _modifiers.get(team, []):
		if m["type"] == ModType.REGEN_MULT:
			rate *= m["value"]
	return rate

# Cena karty po modifikatoroch. Vsetky COST_REDUCE sa SCITAVAJU. Clamp na 0
# (karta zadarmo je legitimny vysledok).
func resolve_cost(team: String, card_id: StringName) -> int:
	var card := CardDB.get_card(card_id)
	if card == null:
		push_error("EnergySystem: neznama karta '%s'" % card_id)
		return 0
	var cost := float(card.cost)
	for m in _modifiers.get(team, []):
		if m["type"] == ModType.COST_REDUCE:
			cost -= m["value"]
	return maxi(0, int(cost))

func can_afford(team: String, card_id: StringName) -> bool:
	return get_energy(team) >= float(resolve_cost(team, card_id))

# Atomicky check + spend na jednom mieste — volajuci NIKDY nesmie odpocitavat
# energiu sam. Server bude robit presne toto zo spravy {card_id, pos, team}.
func try_spend(team: String, card_id: StringName) -> bool:
	if not can_afford(team, card_id):
		return false
	_set_energy(team, get_energy(team) - float(resolve_cost(team, card_id)))
	return true

func add_energy(team: String, amount: float) -> void:
	_set_energy(team, get_energy(team) + amount)

func drain_energy(team: String, amount: float) -> void:
	_set_energy(team, get_energy(team) - amount)

func add_modifier(team: String, type: ModType, value: float, duration: float, tag: StringName) -> void:
	if not _modifiers.has(team):
		_modifiers[team] = []
	_modifiers[team].append({"type": type, "value": value, "time_left": duration, "tag": tag})

func remove_modifier(team: String, tag: StringName) -> void:
	var list: Array = _modifiers.get(team, [])
	for i in range(list.size() - 1, -1, -1):
		if list[i]["tag"] == tag:
			list.remove_at(i)

func has_modifier(team: String, tag: StringName) -> bool:
	for m in _modifiers.get(team, []):
		if m["tag"] == tag:
			return true
	return false

# Jediny zapis do _energy — clamp + emit signalu na jednom mieste.
func _set_energy(team: String, value: float) -> void:
	var clamped := clampf(value, 0.0, MAX_ENERGY)
	_energy[team] = clamped
	var new_int := floori(clamped)
	if new_int != _last_int.get(team, -1):
		_last_int[team] = new_int
		energy_int_changed.emit(team, new_int)

func _process(delta: float) -> void:
	if not _running:
		return
	for team in TEAMS:
		_tick_modifiers(team, delta)
		if _energy.get(team, 0.0) < MAX_ENERGY:
			_set_energy(team, _energy[team] + get_regen_rate(team) * delta)

# Iterovat POZADU — expirovane sa mazu za behu.
func _tick_modifiers(team: String, delta: float) -> void:
	var list: Array = _modifiers.get(team, [])
	for i in range(list.size() - 1, -1, -1):
		var m: Dictionary = list[i]
		if m["time_left"] < 0.0:
			continue   # INFINITE_DURATION — len remove_modifier() ho zrusi
		m["time_left"] -= delta
		if m["time_left"] <= 0.0:
			list.remove_at(i)
