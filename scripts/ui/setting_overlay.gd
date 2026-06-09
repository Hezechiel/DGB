extends Control
class_name SettingsOverlay

signal closed_requested
signal exit_requested

@onready var close_settings: TouchScreenButton = $SettingsPanel/CloseSettings
@onready var exit_button: TextureButton = $ExitButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false

func open() -> void:
	#print("menu opened")
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
