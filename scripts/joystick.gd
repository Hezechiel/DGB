extends Control

enum JoystickType {
	MOVE,
	AIM
}

@export var joystick_type : JoystickType = JoystickType.MOVE
@export var radius: float = 90.0

@onready var knob: Control = $Base/Knob

var _touch_id := -1
var _center : Vector2 = Vector2.ZERO

func _ready() -> void:
	_center = size * 0.5
	_reset_knob()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_process_pos(event.position)
		elif (not event.pressed) and event.index == _touch_id:
			_touch_id =-1
			_set_vector(Vector2.ZERO)
			_reset_knob()
			
	elif event is InputEventScreenDrag:
		if event.index == _touch_id:
			_process_pos(event.position)

func _process_pos(local_pos: Vector2) -> void:
	var offset := local_pos - _center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	
	knob.position = _center + offset - (knob.size * 0.5)
	
	var out := offset /radius
	_set_vector(out)

func _set_vector(v: Vector2) -> void:
	match joystick_type:
		JoystickType.MOVE:
			InputR.move_vector = v
		JoystickType.AIM:
			InputR.aim_vector = v

func _reset_knob() -> void:
	knob.position = _center - (knob.size * 0.5)
