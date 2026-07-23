extends Node

# Healing pody — per-team stav + matematika. ZAMERNE samostatny autoload,
# nie sucast BattleManageru.
#
# TVRDE PRAVIDLO (rovnake ako EnergySystem): tento subor NESMIE poznat sceny,
# nody, Area2D ani Sprite2D. Ziadny preload() sceny, ziadny instantiate(),
# ziadny add_child(). Ciste stav + matematika — na autoritativnom serveri musi
# bezat presne tato logika 1:1. Pozna len pod ID (StringName) a team stringy
# ("player"/"enemy").
#
# HoT bezi do konca bez ohladu na dalsi damage — hrdina moze zomriet na 0 HP
# aj s aktivnym HoT. Smrt ho ale RUSI: hero die() vola cancel_heal(), heal
# nepokracuje pocas respawnu ani po revive.

signal pod_ready(pod_id: StringName)
signal heal_instant(team: String, amount: float)
signal heal_tick(team: String, amount: float, remaining: float)
signal heal_started(team: String, total_amount: float)
signal heal_ended(team: String)

var _pods: Dictionary = {}          # pod_id -> {ready, cooldown_left, respawn_cooldown}
var _active_heals: Dictionary = {}  # team -> {remaining: float, rate: float}

# Volane z arena._enter_tree() — rovnaka pastca ako architecture.md §6,
# samostatny autoload = samostatny reset.
func reset_match_state() -> void:
	_pods.clear()
	_active_heals.clear()

# Volane raz z _ready() kazdeho podu. initial_delay = sekundy do prvej
# dostupnosti; respawn_cooldown = sekundy po kazdom pouziti.
func register_pod(pod_id: StringName, initial_delay: float, respawn_cooldown: float) -> void:
	_pods[pod_id] = {
		"ready": false,
		"cooldown_left": initial_delay,
		"respawn_cooldown": respawn_cooldown,
	}

func is_pod_ready(pod_id: StringName) -> bool:
	return _pods.get(pod_id, {}).get("ready", false)

# Jediny vstupny bod pre heal — instant + HoT v jednom volani, rovnaky tvar
# ako EnergySystem.try_spend() (jedine miesto ktore sa dotyka energie).
func trigger_heal(team: String, instant_amount: float, hot_total: float, hot_duration: float) -> void:
	if instant_amount > 0.0:
		heal_instant.emit(team, instant_amount)
	if hot_total > 0.0 and hot_duration > 0.0:
		_active_heals[team] = {"remaining": hot_total, "rate": hot_total / hot_duration}
		heal_started.emit(team, hot_total)

# Pod ju vola hned po trigger_heal() — startuje vlastny cooldown.
# single_use pody TOTO NEVOLAJU (queue_free-uju sa, pozri healing_pod.gd).
func consume_pod(pod_id: StringName) -> void:
	if not _pods.has(pod_id):
		return
	_pods[pod_id]["ready"] = false
	_pods[pod_id]["cooldown_left"] = _pods[pod_id]["respawn_cooldown"]

# Zrusi aktivny HoT timu (smrt hrdinu). Emitne heal_ended, takze vizualy
# (pending pas na health bare) sa zhasnu tou istou cestou ako pri normalnom
# dobehnuti healu.
func cancel_heal(team: String) -> void:
	if not _active_heals.has(team):
		return
	_active_heals.erase(team)
	heal_ended.emit(team)

func _process(delta: float) -> void:
	for pod_id in _pods.keys():
		var p: Dictionary = _pods[pod_id]
		if p["ready"]:
			continue
		p["cooldown_left"] -= delta
		if p["cooldown_left"] <= 0.0:
			p["ready"] = true
			pod_ready.emit(pod_id)

	# keys() vracia novy Array — erase pocas iteracie je bezpecny
	for team in _active_heals.keys():
		var h: Dictionary = _active_heals[team]
		var amount: float = minf(h["rate"] * delta, h["remaining"])
		h["remaining"] -= amount
		if amount > 0.0:
			heal_tick.emit(team, amount, h["remaining"])
		if h["remaining"] <= 0.0:
			_active_heals.erase(team)
			heal_ended.emit(team)
