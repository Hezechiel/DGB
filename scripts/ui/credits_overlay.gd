extends Control
class_name CreditsOverlay

signal closed

@onready var close_credits: TouchScreenButton = $CreditsPanel/CloseCredits

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	visible = false

func open() -> void:
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func _on_close_credits_pressed() -> void:
	close()
