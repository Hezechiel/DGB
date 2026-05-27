extends Camera2D

# Clamp camera so it can't scroll past the TileMap extents.
# Adjust these to match your TileMap's world bounds.
@export var bounds_min: Vector2 = Vector2(-600, -400)
@export var bounds_max: Vector2 = Vector2(600, 400)

# Minimum finger travel before we commit to a drag (avoids accidental pans on taps).
@export var drag_threshold: float = 8.0

var _touch_id := -1
var _drag_anchor_world: Vector2
var _touch_start_screen: Vector2
var _is_dragging := false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_touch_start_screen = event.position
			_drag_anchor_world = _screen_to_world(event.position)
			_is_dragging = false
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			_is_dragging = false

	elif event is InputEventScreenDrag and event.index == _touch_id:
		if not _is_dragging:
			if event.position.distance_to(_touch_start_screen) >= drag_threshold:
				_is_dragging = true
		if _is_dragging:
			var current_world := _screen_to_world(event.position)
			position -= current_world - _drag_anchor_world
			_clamp_to_bounds()

func _clamp_to_bounds() -> void:
	position.x = clampf(position.x, bounds_min.x, bounds_max.x)
	position.y = clampf(position.y, bounds_min.y, bounds_max.y)

# Screen pixel → world coordinate, accounting for camera position and zoom.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos
