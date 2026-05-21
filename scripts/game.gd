extends Node2D


@onready var setting_overlay: SettingsOverlay = $UI/SettingOverlay
@onready var pause_button: TouchScreenButton = $MobileControls/Root/PauseAnchor/PauseButton
@onready var mobile_controls: CanvasLayer = $MobileControls
@onready var exit_button: TouchScreenButton = $UI/ExitButton

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pause_button.pressed.connect(_on_pause_pressed)


func _on_pause_pressed() -> void:
	#print("menu opened")
	get_tree().paused = true
	mobile_controls.visible = false
	exit_button.visible = true
	setting_overlay.open()


func _on_setting_overlay_close_requested() -> void:
	setting_overlay.close()
	exit_button.visible = false
	mobile_controls.visible = true
	get_tree().paused = false


func _on_exit_button_pressed() -> void:
	setting_overlay.close()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
