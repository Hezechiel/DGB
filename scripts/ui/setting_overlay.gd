extends Control
class_name SettingsOverlay

signal closed_requested
signal exit_requested

@onready var close_settings: TouchScreenButton = $SettingsPanel/CloseSettings
@onready var exit_button: TextureButton = $ExitButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	exit_button.pressed.connect(_on_exit_button_pressed)
	visible = false

#show_return_to_mainmenu_button sluzi na skritie alebo ukazanie Main Menu tlacidla
#toto tlacidlo nie je vzdy ziaduce na obrazovke
func open(show_return_to_mainmenu_button: bool = true) -> void:
	#print("menu opened")
	exit_button.visible = show_return_to_mainmenu_button
	visible = true

func close() -> void:
	#print("Close settings overlay function firred")
	visible = false
	#closed.emit()

func _on_close_settings_pressed() -> void:
	#print("Close_request emited")
	closed_requested.emit()

func _on_exit_button_pressed() -> void:
	exit_requested.emit()
