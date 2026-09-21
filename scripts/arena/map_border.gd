@tool
extends StaticBody2D
## Generates a smooth, symmetric "potato/hourglass" collision outline —
## two rounded lobes (base areas) joined by a pinched waist (funnel) —
## as ONE closed CollisionPolygon2D. Every map's border is an instance
## of MapBorder.tscn with its own parameter values; the shape family
## (curve math) is shared so borders stay consistent across maps
## instead of each being hand-traced (see map_authoring_guide.md's
## complaint about protection_zone having no shared formula — don't
## repeat that here).

## X half-extent — how far each lobe's tip reaches from the center.
@export var half_length: float = 460.0:
	set(value):
		half_length = value
		if is_inside_tree():
			_regenerate_polygon()

## 0-1, where along half_length the lobe reaches its widest point.
@export var lobe_x_ratio: float = 0.65:
	set(value):
		lobe_x_ratio = value
		if is_inside_tree():
			_regenerate_polygon()

## Y half-extent at the lobe's widest point.
@export var lobe_half_height: float = 305.0:
	set(value):
		lobe_half_height = value
		if is_inside_tree():
			_regenerate_polygon()

## Y half-extent at the center pinch (x=0) — the waist of the hourglass.
@export var waist_half_height: float = 150.0:
	set(value):
		waist_half_height = value
		if is_inside_tree():
			_regenerate_polygon()

## Y half-extent at the very end (x=±half_length). Keeps the tip a
## flattened rounded cap instead of coming to a sharp point.
@export var tip_half_height: float = 60.0:
	set(value):
		tip_half_height = value
		if is_inside_tree():
			_regenerate_polygon()

## 0-1, Catmull-Rom-style tangent scale for curve smoothness. Higher =
## rounder/more overshoot between anchors, lower = closer to straight
## segments between them.
@export var handle_strength: float = 0.1:
	set(value):
		handle_strength = value
		if is_inside_tree():
			_regenerate_polygon()

## Passed straight to Curve2D.tessellate() — subdivision stages per segment.
@export var tessellate_stages: int = 5:
	set(value):
		tessellate_stages = value
		if is_inside_tree():
			_regenerate_polygon()

## Passed straight to Curve2D.tessellate() — max angle error tolerance.
@export var tessellate_tolerance_degrees: float = 4.0:
	set(value):
		tessellate_tolerance_degrees = value
		if is_inside_tree():
			_regenerate_polygon()

@onready var _collision: CollisionPolygon2D = $CollisionPolygon2D


func _ready() -> void:
	_regenerate_polygon()
	if not Engine.is_editor_hint():
		collision_layer = 4 # bit 3 "structures"
		collision_mask = 0 # border is static; it doesn't need to detect anything


func _regenerate_polygon() -> void:
	if not _collision:
		return

	# 10 anchors, local space, origin-centered. Fully symmetric under both
	# X-mirror and Y-mirror by construction — two lobes joined by a waist.
	var pts: Array[Vector2] = [
		Vector2(0, waist_half_height),
		Vector2(half_length * lobe_x_ratio, lobe_half_height),
		Vector2(half_length, tip_half_height),
		Vector2(half_length, -tip_half_height),
		Vector2(half_length * lobe_x_ratio, -lobe_half_height),
		Vector2(0, -waist_half_height),
		Vector2(-half_length * lobe_x_ratio, -lobe_half_height),
		Vector2(-half_length, -tip_half_height),
		Vector2(-half_length, tip_half_height),
		Vector2(-half_length * lobe_x_ratio, lobe_half_height),
	]
	var count := pts.size()

	# Central-difference tangent, scaled by /3 (the standard Hermite→Bezier
	# handle-length conversion) on top of handle_strength. Skipping the /3
	# leaves the handle roughly 3x too long at sharp anchors (e.g. the
	# lobe-to-tip drop), which makes that single Bezier segment loop back
	# on itself — self-intersecting geometry that CollisionPolygon2D's
	# Solids build_mode can't decompose ("Convex decomposing failed!").
	var curve := Curve2D.new()
	for i in range(count):
		var next := pts[(i + 1) % count]
		var prev := pts[(i - 1 + count) % count]
		var tangent := (next - prev) * handle_strength / 3.0
		curve.add_point(pts[i], -tangent, tangent)

	# Curve2D doesn't wrap on its own — close the loop explicitly by
	# repeating the first anchor as an 11th point, s tangentom vypočítaným
	# rovnako (pts[1] ako "next", pts[9] ako "prev").
	var closing_tangent := (pts[1] - pts[count - 1]) * handle_strength / 3.0
	curve.add_point(pts[0], -closing_tangent, closing_tangent)

	var baked := curve.tessellate(tessellate_stages, tessellate_tolerance_degrees)
	baked.remove_at(baked.size() - 1) # drop duplicate closing vertex; CollisionPolygon2D
										# closes its last point back to the first implicitly
	_collision.polygon = baked
