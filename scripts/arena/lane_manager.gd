extends Node

# LaneManager — centralne ulozisko waypointov pre obe lany
# Klucom je retazec "team_lane" napr. "player_top", "enemy_bot"
# Waypointy su v poradí od spawnu k nepriatelskej baze
# Paths are registered at runtime by arena.gd reading scene-placed Marker2D nodes

var _paths: Dictionary = {}

# Vrati pole waypointov pre dany tim a lanu, alebo prazdne pole ak neexistuje
func get_lane_path(team: String, lane: String) -> Array:
	var key := team + "_" + lane
	if _paths.has(key):
		return _paths[key]
	push_error("LaneManager: neznamy path key: " + key)
	return []

func register_lane_path(team: String, lane: String, points: Array) -> void:
	_paths[team + "_" + lane] = points
