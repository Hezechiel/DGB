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

	if guard.has_signal("destroyed"):
		guard.destroyed.connect(_on_guard_destroyed)

	# Waypoints a strazene struktury su sourozenci v strome (napr. Waypoints
	# vs PlayerStructures) — Godot vola _ready() na sourozencoch v poradi
	# podla scene tree, nie podla zavislosti, takze guard.hp nemusi byt este
	# nastavene na max_hp v tomto bode (default int = 0 by sa vyhodnotil ako
	# "uz mrtva"). call_deferred pocka, kym vsetky _ready() v scene dobehnu.
	call_deferred("_check_initial_guard_state", guard)

func _check_initial_guard_state(guard: Node) -> void:
	# edge case: vezicka uz bola znicena pred nacitanim tejto sceny
	if is_instance_valid(guard) and "hp" in guard and guard.hp <= 0:
		_active = false

func is_active() -> bool:
	return _active

func _on_guard_destroyed() -> void:
	_active = false
