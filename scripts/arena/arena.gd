extends Node2D

@onready var hud: HUD = $HUD
@onready var move_marker: Node2D = $MoveMarker

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

func _ready() -> void:
	hud.exit_requested.connect(_on_hud_exit_requested)
	BattleManager.match_ended.connect(_on_match_ended)

func _unhandled_input(event: InputEvent) -> void:
	# Tap-to-move: tap mimo UI (UI eventy sem nedojdu, su handled v _gui_input)
	if event is InputEventScreenTouch and event.pressed:
		var world_pos: Vector2 = get_canvas_transform().affine_inverse() * event.position
		InputR.set_move_target(world_pos)
		move_marker.show_at(world_pos)

func _on_hud_exit_requested() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_match_ended(_winner: String) -> void:
	get_tree().change_scene_to_file("res://scenes/menu/MatchEndScreen.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T:
			$Turret.take_damage(80)
		if event.keycode == KEY_Y:
			$PlayerBase.take_damage(500)
