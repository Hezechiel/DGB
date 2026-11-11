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

# === DOUBLE-TAP (dash) ===
# Gesture state: dva rychle tapy na zem blizko seba = dash. Cisty stav,
# ziadne scene referencie ani ine autoloady. Pozicia v SCREEN space (viewport
# px), nie world — tolerancia prsta nezavisi od kamery.
const DOUBLE_TAP_WINDOW_MS := 280
const DOUBLE_TAP_MAX_DIST := 40.0   # viewport px (screen space, NIE world)
var _last_tap_ms: int = -1
var _last_tap_pos: Vector2 = Vector2.ZERO

# true = tento tap uzavrel double-tap. Inak si ho zapamata ako prvy tap paru.
func register_ground_tap(screen_pos: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	if _last_tap_ms >= 0 and now - _last_tap_ms <= DOUBLE_TAP_WINDOW_MS \
			and screen_pos.distance_squared_to(_last_tap_pos) <= DOUBLE_TAP_MAX_DIST * DOUBLE_TAP_MAX_DIST:
		_last_tap_ms = -1   # reset po zasahu — triple tap = jeden dash, 3. tap zacne novy par
		return true
	_last_tap_ms = now
	_last_tap_pos = screen_pos
	return false

func reset_double_tap() -> void:
	_last_tap_ms = -1
