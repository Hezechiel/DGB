extends Node2D
class_name ChainLightningFx

# Placeholder vizual Chain Lightning — lomena ciara caster -> zasiahnute ciele,
# zmizne za FADE_SECONDS. Postavene v kode, ziadna scena. Uzol sedi v originu
# pod arena_root, body su vo world suradniciach. Patri scene, ziadny reset.

const FADE_SECONDS := 0.25
const ZIGZAG_OFFSET := 4.0
const GLOW_COLOR := Color(0.55, 0.8, 1.0, 0.6)
const CORE_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var _points := PackedVector2Array()

func setup(points: PackedVector2Array) -> void:
	_points = _zigzag(points)
	queue_redraw()

func _ready() -> void:
	z_index = 50  # nad unitmi, pod desaturate overlayom (100)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)

func _draw() -> void:
	if _points.size() < 2:
		return
	draw_polyline(_points, GLOW_COLOR, 3.0)
	draw_polyline(_points, CORE_COLOR, 1.5)

# Kazdy segment rozdeli na 3 casti, 2 vnutorne body posunute kolmo +/-,
# striedavo — deterministicky "blesk" bez RNG.
static func _zigzag(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	var side := 1.0
	for idx in range(1, points.size()):
		var a := points[idx - 1]
		var b := points[idx]
		var normal := (b - a).orthogonal().normalized()
		out.append(a.lerp(b, 1.0 / 3.0) + normal * ZIGZAG_OFFSET * side)
		out.append(a.lerp(b, 2.0 / 3.0) - normal * ZIGZAG_OFFSET * side)
		out.append(b)
		side = -side
	return out
