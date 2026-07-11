extends Node

# Projektovy register jednotiek/struktur podla timu. Oddeleny od
# enemy_spawner.enemies (ten ostava len pre separation steering).
# Sluzi systemom: win/lose podmienky, allied minion AI, minimapa...

# Emitovany ked zakladna jedneho timu je znicena — arena.gd pocuva a zmeni scenu
signal match_ended(winner_team: String)

# Jednotky podla timu (hrdinovia + sumonovane jednotky)
var team_player: Array[Node2D] = []
var team_enemy: Array[Node2D] = []

# Zakladne
var player_base: Node2D = null
var enemy_base: Node2D = null

# Veze podla timu a pruhu — na vyhodnotenie ked je pruh vycisteny
# Struktura: { "player": { "top": [...], "bot": [...] }, "enemy": { ... } }
var _turrets: Dictionary = {
	"player": {"top": [], "bot": []},
	"enemy":  {"top": [], "bot": []}
}

# Ulozit vysledok zapasu pre MatchEndScreen
var last_winner: String = ""

# Arena root nastavuje arena.gd vo svojom _ready() — BattleManager je autoload
# bez vlastnej scenografie, takze potrebuje referenciu kam pridat spawnute uzly.
var arena_root: Node = null

# --- Registracia jednotiek ---

func register(unit: Node2D, team: String) -> void:
	var list := team_player if team == "player" else team_enemy
	if not list.has(unit):
		list.append(unit)
		unit.tree_exited.connect(func(): unregister(unit, team), CONNECT_ONE_SHOT)

func unregister(unit: Node2D, team: String) -> void:
	var list := team_player if team == "player" else team_enemy
	list.erase(unit)

func is_team_alive(team: String) -> bool:
	var list := team_player if team == "player" else team_enemy
	return list.size() > 0

# --- Registracia vez ---

func register_turret(turret: Node2D, team: String, lane: String) -> void:
	if _turrets.has(team) and _turrets[team].has(lane):
		_turrets[team][lane].append(turret)

# Volane z turret._on_destroyed()
func on_turret_destroyed(turret_team: String, lane: String) -> void:
	# Ak je pruh timu vycisteny, ich vlastna zakladna sa stane zranitelnou
	if _is_lane_cleared(turret_team, lane):
		_set_base_vulnerable(turret_team)

func _is_lane_cleared(team: String, lane: String) -> bool:
	# Pruh je vycisteny ak nemaju ziadnu zivu vezu v nom
	var lane_turrets: Array = _turrets[team][lane]
	for t in lane_turrets:
		if is_instance_valid(t) and t.hp > 0:
			return false
	return true

func _set_base_vulnerable(team: String) -> void:
	var base := player_base if team == "player" else enemy_base
	if base and is_instance_valid(base):
		base.set_vulnerable()

# --- Registracia zakladni ---

func register_base(base: Node2D, team: String) -> void:
	if team == "player":
		player_base = base
	else:
		enemy_base = base

# Volane z base._on_destroyed()
func on_base_destroyed(destroyed_team: String) -> void:
	last_winner = "enemy" if destroyed_team == "player" else "player"
	match_ended.emit(last_winner)

# --- March ciel pre jednotky ---

# Vrati najblizsiu zivu strukturu (veza z ktorejkolvek lany alebo baza)
# patriacu defending_team, meranu od from_pos. Ziadna lane logika ani
# priorita — cisto najblizsia ziva struktura. Null ak nic nezije
# (nemalo by nastat, znicenie bazy konci zapas, ale osetrene pre istotu).
func get_nearest_structure(defending_team: String, from_pos: Vector2) -> Node2D:
	var candidates: Array = []
	if _turrets.has(defending_team):
		candidates.append_array(_turrets[defending_team]["top"])
		candidates.append_array(_turrets[defending_team]["bot"])
	var base := player_base if defending_team == "player" else enemy_base
	if base != null:
		candidates.append(base)

	var nearest: Node2D = null
	var nearest_dist := INF
	for structure in candidates:
		if not is_instance_valid(structure) or structure.hp <= 0:
			continue
		var d: float = from_pos.distance_squared_to(structure.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = structure
	return nearest

# --- Spawn (jediny vstupny bod pre vytvaranie jednotiek) ---

# Jediny spawn entry point pre jednotky. Resolvne CardData → UnitData cez
# CardDB, instancuje archetype scenu, nakonfiguruje ju PRED vstupom do stromu
# (instantiate → configure → add_child). Buduci network handler a
# drag-to-deploy volaju tuto funkciu — ziadne ine miesto uz jednotky
# neinstancuje priamo.
func spawn_unit(card_id: StringName, pos: Vector2, team: String) -> Node:
	if arena_root == null:
		push_error("BattleManager.spawn_unit: arena_root nie je nastaveny")
		return null

	var card := CardDB.get_card(card_id)
	if card == null or card.unit_data == null:
		push_error("BattleManager.spawn_unit: card '%s' nema priradene unit_data" % card_id)
		return null

	var unit_data := card.unit_data
	if unit_data.archetype_scene == null:
		push_error("BattleManager.spawn_unit: unit_data '%s' nema archetype_scene" % unit_data.id)
		return null

	var unit := unit_data.archetype_scene.instantiate()
	unit.configure(unit_data, team)
	unit.global_position = pos
	arena_root.add_child.call_deferred(unit)
	return unit
