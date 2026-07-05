class_name LaneWaypoint
extends Node2D

# Waypoint na lane-ceste. Ak je navesany na strukturu (vezicku) cez
# guard_structure_path, stane sa neaktivnym akonahle ta struktura zomrie —
# marchujuce jednotky (unit.gd) potom tento bod preskocia namiesto toho aby
# sa v nom zasekli alebo mierili na uz mrtvu vezicku.
# Prazdne guard_structure_path (WP1/WP3/WP5) = vzdy aktivny plain waypoint.
@export var guard_structure_path: NodePath = NodePath("")

var _active: bool = true

func _ready() -> void:
	if guard_structure_path.is_empty():
		return

	var guard := get_node_or_null(guard_structure_path)
	if guard == null:
		push_error("LaneWaypoint: guard_structure_path neplatny na " + str(get_path()))
		return

	# edge case: vezicka uz bola znicena pred nacitanim tejto sceny
	if "hp" in guard and guard.hp <= 0:
		_active = false
		return

	if guard.has_signal("destroyed"):
		guard.destroyed.connect(_on_guard_destroyed)

func is_active() -> bool:
	return _active

func _on_guard_destroyed() -> void:
	_active = false
