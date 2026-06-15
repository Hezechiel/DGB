extends Node

# Projektovy register jednotiek/struktur podla timu. Oddeleny od
# enemy_spawner.enemies (ten ostava len pre separation steering).
# Sluzi buducim systemom: win/lose podmienky, allied minion AI, minimapa...

var team_player: Array[Node2D] = []
var team_enemy: Array[Node2D] = []

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
