extends Node2D
# Runs inside a CanvasLayer — position is in screen space (pixels), not world space.
# Follows the active finger with lerp lag. Floats in place when idle.

@export var smoothing: float = 8.0
@export var idle_float_speed: float = 1.5
@export var idle_float_amplitude: float = 6.0

# Swap SpriteFrames on this node to change god type (hand / eye / etc.) — no script changes needed.
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

enum State { IDLE, HOVER }
var _state := State.IDLE

var _target_pos: Vector2
var _base_pos: Vector2      # screen position around which idle float oscillates
var _float_time := 0.0
var _touch_id := -1

func _ready() -> void:
	_target_pos = get_viewport().get_visible_rect().size * 0.5
	_base_pos = _target_pos
	position = _target_pos

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_target_pos = event.position
			_state = State.HOVER
			if sprite:
				sprite.play("hover")
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			_state = State.IDLE
			_base_pos = position      # float around where the hand currently is
			_float_time = 0.0         # restart phase so sin starts at 0 (no position jump)
			if sprite:
				sprite.play("idle")

	elif event is InputEventScreenDrag and event.index == _touch_id:
		_target_pos = event.position

func _process(delta: float) -> void:
	var dest: Vector2
	if _state == State.IDLE:
		_float_time += delta
		dest = _base_pos + Vector2(0.0, sin(_float_time * idle_float_speed) * idle_float_amplitude)
	else:
		dest = _target_pos

	position = position.lerp(dest, smoothing * delta)
