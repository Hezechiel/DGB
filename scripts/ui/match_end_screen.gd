extends Control

const MAIN_MENU := "res://scenes/menu/MainMenu.tscn"

@onready var winner_label: Label = $VBoxContainer/WinnerLabel
@onready var menu_button: Button  = $VBoxContainer/MenuButton


func _ready() -> void:
	var winner := BattleManager.last_winner
	if winner == "draw":
		winner_label.text = "DRAW MATCH"
	else:
		winner_label.text = winner.to_upper() + " TEAM WINS!"
	menu_button.pressed.connect(_on_menu_button_pressed)
	# Vitazstvo/prehra z pohladu LOKALNEHO hraca (last_winner je "player"/"enemy"/"draw").
	match winner:
		"player":
			AudioManager.play_stinger(&"stinger_victory", &"menu")
		"enemy":
			AudioManager.play_stinger(&"stinger_defeat", &"menu")
		_:
			AudioManager.play_music(&"menu")


func _on_menu_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
