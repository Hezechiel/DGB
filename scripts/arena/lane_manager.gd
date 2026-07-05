extends Node

# LaneManager — centralne ulozisko waypointov pre obe lany
# Klucom je retazec "team_lane" napr. "player_top", "enemy_bot"
# Ulozene su LaneWaypoint node referencie (nie Vector2) v poradí od spawnu
# k nepriatelskej baze — kazdy node vie povedat is_active() (pozri
# lane_waypoint.gd), takze marchujuca jednotka moze preskocit body strazene
# uz znicenou vezickou. Paths are registered at runtime by arena.gd reading
# scene-placed waypoint nodes under $Waypoints.

var _paths: Dictionary = {}

# Fallback ciel ked jednotke dojdu/nezostanu ziadne aktivne waypointy —
# team -> Vector2 (pozicia nepriatelskej bazy z pohladu daneho timu)
var _final_targets: Dictionary = {}

# Vrati pole waypointov pre dany tim a lanu, alebo prazdne pole ak neexistuje
func get_lane_path(team: String, lane: String) -> Array:
	var key := team + "_" + lane
	if _paths.has(key):
		return _paths[key]
	push_error("LaneManager: neznamy path key: " + key)
	return []

func register_lane_path(team: String, lane: String, points: Array) -> void:
	_paths[team + "_" + lane] = points

func register_final_target(team: String, pos: Vector2) -> void:
	_final_targets[team] = pos

func get_final_target(team: String) -> Vector2:
	return _final_targets.get(team, Vector2.ZERO)
