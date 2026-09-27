extends HSlider

# Jeden slider script pre vsetky hlasitosti — audio_bus_name vyberie ktory
# kanal ovlada (Music / SFX / Voice). Hodnota zije v Settings (single source
# of truth), na busy ju aplikuje AudioManager; tento script k busom
# nepristupuje priamo.

@export var audio_bus_name: String

var _is_dragging: bool = false

func _ready() -> void:
	# obnov slider z ulozeneho nastavenia — no_signal, aby samotne otvorenie
	# overlayu nespustilo zapis do Settings
	set_value_no_signal(AudioManager.get_volume(StringName(audio_bus_name)))
	value_changed.connect(_on_value_changed)

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
	AudioManager.set_volume(StringName(audio_bus_name), val)
