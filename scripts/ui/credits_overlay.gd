extends FramedOverlay
class_name CreditsOverlay

signal closed

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()  # FramedOverlay: close button, god layout, frame/title
	visible = false

func open() -> void:
	_frame_opened()
	visible = true

func close() -> void:
	visible = false
	_frame_closed()  # skryty overlay nema co animovat
	closed.emit()

func _on_frame_close_pressed() -> void:
	close()
