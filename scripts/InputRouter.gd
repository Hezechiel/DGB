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

# Touch index ktoreho release sa ma ignorovat (napr. ked press tapnutia bol
# pouzity na vyber primary_target cez hurtbox — release toho isteho tapnutia
# nesmie spustit tap-to-move). One-shot: po prvej kontrole sa flag vymaze.
var suppress_release_index: int = -1

func suppress_release_of_touch(touch_index: int) -> void:
	suppress_release_index = touch_index

# Index-agnosticka verzia — ked nemame k dispozicii touch index (napr. TouchScreenButton
# emituje len "pressed" bez indexu). Ignoruje najblizsi nasledujuci release.
var _suppress_next_release: bool = false

func suppress_next_release() -> void:
	_suppress_next_release = true

func is_release_suppressed(touch_index: int) -> bool:
	if _suppress_next_release:
		_suppress_next_release = false
		return true
	if touch_index == suppress_release_index:
		suppress_release_index = -1
		return true
	return false
