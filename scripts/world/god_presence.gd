extends Node2D

@export var smoothing: float = 8.0
@export var idle_float_speed: float = 1.5
@export var idle_float_amplitude: float = 6.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

enum State { IDLE, HOVER }
var _state := State.IDLE
var _touch_id := -1
var _move_dest: Vector2   # always tracks the last intended destination
var _tween: Tween


func _ready() -> void:
	_move_dest = get_viewport().get_visible_rect().size * 0.5
	position = _move_dest
	_start_idle_float(_move_dest)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_state = State.HOVER
			sprite.play("hover")
			_move_to(event.position)

		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			_state = State.IDLE
			sprite.play("idle")
			_finish_then_float()   # let hand reach dest first, then float

	elif event is InputEventScreenDrag and event.index == _touch_id:
		_move_to(event.position)


func _move_to(dest: Vector2) -> void:
	_move_dest = dest
	_kill_tween()
	_tween = create_tween()
	var duration := clampf(position.distance_to(dest) / 800.0, 0.05, 0.2)
	_tween.tween_property(self, "position", dest, duration).set_trans(Tween.TRANS_SINE)


func _finish_then_float() -> void:
	# Complete the move to _move_dest, then chain into the idle loop.
	# If already there, the property step is instant.
	_kill_tween()
	_tween = create_tween()
	var duration := clampf(position.distance_to(_move_dest) / 500.0, 0.10, 0.35)
	_tween.tween_property(self, "position", _move_dest, duration).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_begin_loop_float.bind(_move_dest))


func _begin_loop_float(base: Vector2) -> void:
	# Called from a finished tween — create a fresh looping one, no kill needed.
	_tween = create_tween().set_loops()
	var half := 1.0 / idle_float_speed
	_tween.tween_property(self, "position", base + Vector2(0, -idle_float_amplitude), half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "position", base + Vector2(0,  idle_float_amplitude), half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_idle_float(base: Vector2) -> void:
	_kill_tween()
	_begin_loop_float(base)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
