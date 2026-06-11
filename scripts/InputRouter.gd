extends Node
class_name InputRouter

# Tap-to-move: ciel vo world suradniciach (plati len ked has_move_target == true)
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false

func set_move_target(world_pos: Vector2) -> void:
	move_target = world_pos
	has_move_target = true

func clear_move_target() -> void:
	has_move_target = false
