extends Node2D

@export var village_name: String = "Village"
@export var starting_faith: float = 0.0

var faith: float = 0.0
var fear: float = 0.0
var prosperity: float = 50.0

@onready var name_label: Label = $NameLabel
@onready var faith_label: Label = $FaithLabel
@onready var area: Area2D = $Area2D

func _ready() -> void:
	faith = starting_faith
	name_label.text = village_name
	_update_visuals()
	area.input_event.connect(_on_input_event)

# Called by WorldSimulation (step 7) for online ticks and offline catch-up.
func tick(delta_time: float) -> void:
	faith = maxf(faith - 0.5 * delta_time, 0.0)
	_update_visuals()

# Called by world_map.gd when a spell gesture resolves over this village (step 4+).
func receive_spell(spell_type: String) -> void:
	match spell_type:
		"bless": faith = minf(faith + 15.0, 100.0)
		"rain":  prosperity = minf(prosperity + 10.0, 100.0)
		"smite": fear = minf(fear + 20.0, 100.0)
	_update_visuals()

func _update_visuals() -> void:
	faith_label.text = "Faith: %.0f" % faith

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		print("[Village] tapped: ", village_name, "  faith=%.0f" % faith)
