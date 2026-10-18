extends Node2D
class_name TidalWaveFx

# Placeholder vizual Tidal Wave — vyplneny kuzel (vysek) pred Poseidonom so
# svetlejsou hranou oblúka, zmizne za FADE_SECONDS. Postavene v kode, ziadna
# scena (vzor ChainLightningFx). Uzol sedi v originu pod arena_root, body su
# vo world suradniciach. Patri scene, ziadny reset.

const FADE_SECONDS := 0.35
const ARC_POINTS := 16
const FILL_COLOR := Color(0.3, 0.6, 1.0, 0.35)
const EDGE_COLOR := Color(0.7, 0.9, 1.0, 0.9)

var _arc := PackedVector2Array()
var _poly := PackedVector2Array()

func setup(origin: Vector2, dir: Vector2, radius: float, angle_deg: float) -> void:
	var half := deg_to_rad(angle_deg / 2.0)
	var start := dir.angle() - half
	_arc.clear()
	for idx in ARC_POINTS + 1:
		var a := start + (2.0 * half) * float(idx) / float(ARC_POINTS)
		_arc.append(origin + Vector2.from_angle(a) * radius)
	_poly = PackedVector2Array([origin])
	_poly.append_array(_arc)
	queue_redraw()

func _ready() -> void:
	z_index = 50  # nad unitmi, pod desaturate overlayom (100)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)

func _draw() -> void:
	if _poly.size() < 3:
		return
	draw_colored_polygon(_poly, FILL_COLOR)
	draw_polyline(_arc, EDGE_COLOR, 2.0)
