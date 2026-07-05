extends Node2D

@onready var hud: HUD = $HUD
@onready var move_marker: Node2D = $MoveMarker
@onready var arena_camera: Camera2D = $ArenaCamera
@onready var player: CharacterBody2D = $Player

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

func _ready() -> void:
	_register_lane_paths()
	hud.exit_requested.connect(_on_hud_exit_requested)
	hud.recenter_camera_requested.connect(_on_recenter_camera_requested)
	BattleManager.match_ended.connect(_on_match_ended)
	# 2D object picking je defaultne vypnute — bez neho Area2D.input_event
	# (tap na enemy/turret/base hurtbox) nikdy nevystreli
	get_viewport().physics_object_picking = true
	get_viewport().physics_object_picking_sort = true

func _unhandled_input(event: InputEvent) -> void:
	# Tap-to-move: tap mimo UI (UI eventy sem nedojdu, su handled v _gui_input)
	if event is InputEventScreenTouch and not event.pressed:
		# release tapnutia ktoreho press bol pouzity na vyber primary_target sa ignoruje
		if InputR.is_release_suppressed(event.index):
			return
		var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
		InputR.set_move_target(world_pos)
		player.on_new_move_command() # novy tap-to-move zrusi manualny lock na cieli
		move_marker.show_at(world_pos)

func _on_hud_exit_requested() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_recenter_camera_requested() -> void:
	arena_camera.recenter_on_player()

func _on_match_ended(_winner: String) -> void:
	get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")

func _register_lane_paths() -> void:
	var lane_map := {"TopLane": "top", "BotLane": "bot"}
	for node_name in lane_map:
		var lane_key: String = lane_map[node_name]
		var container: Node = $Waypoints.get_node(node_name)
		var forward: Array = []
		for marker in container.get_children():
			forward.append(marker) # LaneWaypoint node, nie pozicia — pozri lane_waypoint.gd
		LaneManager.register_lane_path("player", lane_key, forward)
		var reverse := forward.duplicate()
		reverse.reverse()
		LaneManager.register_lane_path("enemy", lane_key, reverse)

	# fallback ciel ked jednotke dojdu aktivne waypointy (znicene vezicky) —
	# march priamo na nepriatelsku bazu
	LaneManager.register_final_target("player", $EnemyBase.global_position)
	LaneManager.register_final_target("enemy", $PlayerBase.global_position)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T:
			$Turret.take_damage(80)
		if event.keycode == KEY_Y:
			$PlayerBase.take_damage(500)
