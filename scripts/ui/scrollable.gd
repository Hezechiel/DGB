# res://ui/scrollable.gd
class_name Scrollable
extends ScrollContainer

# --- Tuning constants ---
const FRICTION        : float = 0.92   # 0.0 = stops instantly, 1.0 = never stops
const MIN_VELOCITY    : float = 5.0    # below this speed, scroll stops completely
const VELOCITY_SCALE  : float = 1.0    # multiply if scroll feels too slow/fast

# --- Internal state ---
var _drag_start     : Vector2
var _scroll_start   : int
var _is_dragging    : bool    = false
var _velocity       : float   = 0.0
var _last_position  : float   = 0.0
var _last_delta     : float   = 0.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# Finger down — reset everything, capture start state
			_drag_start    = event.position
			_scroll_start  = scroll_vertical
			_is_dragging   = true
			_velocity      = 0.0
			_last_position = event.position.y
			_last_delta    = 0.0

		else:
			# Finger up — release and hand off to fling
			_is_dragging = false
			_velocity    = -_last_delta * VELOCITY_SCALE

	elif event is InputEventScreenDrag:
		if _is_dragging:
			# Track delta between frames for fling seed
			_last_delta    = event.position.y - _last_position
			_last_position = event.position.y

			var total_drag = _drag_start.y - event.position.y
			scroll_vertical = _scroll_start + int(total_drag)


func _process(_delta: float) -> void:
	# Only run fling when finger is lifted and velocity is meaningful
	if _is_dragging or abs(_velocity) < MIN_VELOCITY:
		return

	scroll_vertical += int(_velocity)
	_velocity       *= FRICTION
