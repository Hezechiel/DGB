extends Control
class_name SettingsOverlay

signal closed_requested

@onready var close_settings: TouchScreenButton = $SettingsPanel/CloseSettings

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
