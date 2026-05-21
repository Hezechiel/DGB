extends HSlider

@export var audio_bus_name: String

var audio_bus_id: int
var _is_dragging: bool = false

func _ready() -> void:
	audio_bus_id = AudioServer.get_bus_index(audio_bus_name)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = true
			_apply_touch_position(event.position)
		else:
			_is_dragging = false
	
	elif event is InputEventScreenDrag:
		if _is_dragging:
			_apply_touch_position(event.position)

func _apply_touch_position(local_pos: Vector2) -> void:
	# Convert touch X position to 0.0–1.0 range based on slider width
	var touch_ratio = clamp(local_pos.x / size.x, 0.0, 1.0)
	value = min_value + touch_ratio * (max_value - min_value)
	#print(value)

func _on_value_changed(val: float) -> void:
	if audio_bus_id == -1:
		return
	
	if val <= 0.001:
		AudioServer.set_bus_mute(audio_bus_id, true)
	else:
		AudioServer.set_bus_mute(audio_bus_id, false)
		#print(linear_to_db(val))
		AudioServer.set_bus_volume_db(audio_bus_id, linear_to_db(val))


#@export var audio_bus_name : String
#var audio_bus_id : int
#
#func _ready() -> void:
	#audio_bus_id = AudioServer.get_bus_index(audio_bus_name)
#
#func _on_value_changed(value: float) -> void:
	#if audio_bus_id == -1:
		#return
		#
	#if value <= 0.001:
		#AudioServer.set_bus_mute(audio_bus_id, true)
	#else:
		#AudioServer.set_bus_mute(audio_bus_id, false)
		#AudioServer.set_bus_volume_db(audio_bus_id, linear_to_db(value))
