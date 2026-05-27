extends Node2D
# Scene coordinator for the World Map phase.
# Camera drag is handled directly by world_camera.gd.
# Village taps are handled directly by village.gd.
# God Presence following is handled directly by god_presence.gd.
# This script coordinates cross-node logic: spell resolution, faith HUD, etc. (added in later steps).

@onready var locations_layer: Node2D = $LocationsLayer
@onready var god_presence_layer: CanvasLayer = $GodPresenceLayer

func _ready() -> void:
	pass

# Returns all Village nodes currently on the map.
func get_villages() -> Array[Node]:
	return locations_layer.get_children().filter(func(n): return n.has_method("receive_spell"))
