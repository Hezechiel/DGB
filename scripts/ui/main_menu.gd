extends Control

@onready var main_buttons: VBoxContainer = $MainButtons
@onready var start_game_buton: TouchScreenButton = $MainButtons/StartGameButon
@onready var start_arena_buton: TouchScreenButton = $MainButtons/StartArenaButon
@onready var settings_button: TouchScreenButton = $MainButtons/SettingsButton
@onready var credits_button: TouchScreenButton = $MainButtons/CreditsButton

@onready var exit_button: TouchScreenButton = $ExitButton

@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var credits_overlay: CreditsOverlay = $CreditsOverlay

const GAME_SCENE := "res://scenes/world/WorldMap.tscn"
const ARENA_SCENE := "res://scenes/arena/arena.tscn"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Mobile: hide Exit (Android usually doestn need it)
	#if OS.has_feature("android") or OS.has_feature("ios"):
		#$ExitButton.visible = false
	main_buttons.visible = true
	exit_button.visible = true
	start_game_buton.pressed.connect(_on_start_game_buton_pressed)
	start_arena_buton.pressed.connect(_on_start_arena_buton_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	#setting_overlay.visible = false

func _on_start_game_buton_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
	
func _on_start_arena_buton_pressed() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)

func _on_settings_button_pressed() -> void:
	# overlay version
	#get_tree().paused = true
	main_buttons.visible = false
	exit_button.visible = false
	setting_overlay.open()

func _on_credits_button_pressed() -> void:
	# overlay version
	main_buttons.visible = false
	exit_button.visible = false
	credits_overlay.open()
	
func _on_setting_overlay_close_requested() -> void:
	#print("Close_request signal received by main menu")
	setting_overlay.close()
	main_buttons.visible = true
	exit_button.visible = true
	#get_tree().paused = false

func _on_credits_overlay_closed() -> void:
	main_buttons.visible = true
	exit_button.visible = true

func _on_exit_button_pressed() -> void:
	get_tree().quit()
