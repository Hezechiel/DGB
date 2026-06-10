extends Node2D

@onready var hud: HUD = $HUD

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

func _ready() -> void:
	hud.exit_requested.connect(_on_hud_exit_requested)

func _on_hud_exit_requested() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
