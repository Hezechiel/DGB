extends Node2D
# Placeholder preview kruh pre drag-to-deploy. Zelena = da sa deployovat,
# cervena = zakazane miesto. TODO: nahradit realnym previewom jednotky
# (silueta/duch) az budu assety.

@export var radius: float = 24.0
@export var color_valid := Color(0.2, 0.9, 0.3, 0.35)
@export var color_invalid := Color(0.9, 0.2, 0.2, 0.35)

var _is_valid: bool = true

func _ready() -> void:
	visible = false

func show_at(pos: Vector2, is_valid: bool) -> void:
	global_position = pos
	_is_valid = is_valid
	visible = true
	queue_redraw()

func hide_ghost() -> void:
	visible = false

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color_valid if _is_valid else color_invalid)
