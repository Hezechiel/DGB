extends Node2D


@onready var setting_overlay: SettingsOverlay = $UI/SettingOverlay
@onready var pause_button: TouchScreenButton = $MobileControls/Root/PauseAnchor/PauseButton
@onready var mobile_controls: CanvasLayer = $MobileControls

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pause_button.pressed.connect(_on_pause_pressed)
	setting_overlay.exit_requested.connect(_on_setting_overlay_exit_requested)


func _on_pause_pressed() -> void:
	#print("menu opened")
	get_tree().paused = true
	mobile_controls.visible = false
	setting_overlay.open()


func _on_setting_overlay_close_requested() -> void:
	setting_overlay.close()
	mobile_controls.visible = true
	get_tree().paused = false


func _on_setting_overlay_exit_requested() -> void:
	setting_overlay.close()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
