extends Node

# LaneManager — centralne ulozisko waypointov pre obe lany
# Klucom je retazec "team_lane" napr. "player_top", "enemy_bot"
# Waypointy su v poradí od spawnu k nepriatelskej baze
# Hodnoty su hardcodovane pre testovaciu arenu — nahradene Marker2D
# referenciami v nasledujucom tasku

# Suradnice areny:
# PlayerBase x=-360, PlayerTurrets x=-170 (top y=-130, bot y=130)
# EnemyBase  x= 360, EnemyTurrets  x= 170 (top y=-130, bot y=130)
# Viewport: 780x360, limity kamery: x -450..450, y -350..350

var _paths: Dictionary = {}

func _ready() -> void:
	# player_top: lava baza → okolo player top turret → stred → okolo enemy top turret → prava baza
	_paths["player_top"] = [
		Vector2(-280, -100),   # za player spawnom, smer k top turretu
		Vector2(-170, -100),   # vedla player top turret (nie cez turret)
		Vector2(0,    -100),   # stred mapy, top lana
		Vector2( 170, -100),   # vedla enemy top turret
		Vector2( 280, -100),   # pred enemy bazou
	]

	# player_bot: zrkadlo top lany (y kladne = dole)
	_paths["player_bot"] = [
		Vector2(-280,  100),
		Vector2(-170,  100),
		Vector2(0,     100),
		Vector2( 170,  100),
		Vector2( 280,  100),
	]

	# enemy_top: opacny smer oproti player_top
	_paths["enemy_top"] = [
		Vector2( 280, -100),
		Vector2( 170, -100),
		Vector2(0,    -100),
		Vector2(-170, -100),
		Vector2(-280, -100),
	]

	# enemy_bot: opacny smer oproti player_bot
	_paths["enemy_bot"] = [
		Vector2( 280,  100),
		Vector2( 170,  100),
		Vector2(0,     100),
		Vector2(-170,  100),
		Vector2(-280,  100),
	]

# Vrati pole waypointov pre dany tim a lanu, alebo prazdne pole ak neexistuje
func get_lane_path(team: String, lane: String) -> Array:
	var key := team + "_" + lane
	if _paths.has(key):
		return _paths[key]
	push_error("LaneManager: neznamy path key: " + key)
	return []
