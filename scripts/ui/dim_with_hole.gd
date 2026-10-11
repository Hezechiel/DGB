extends Control
class_name DimWithHole

# Fullscreen stmavenie s jednou obdlznikovou dierou podla ineho Controlu.
# Zamerne NIE shader — diera musi byt presna len tam, kde je art nad nou
# priehladny; jej okraje sa schovaju pod nepriehladny ram (hole_pad).

@export var hole_source: Control
@export var dim_color: Color = Color(0, 0, 0, 0.8)
@export var hole_pad: float = 4.0   # screen px; diera sa zvacsi, okraj sa skryje pod ram

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if hole_source:
		# item_rect_changed = zmena pozicie AJ velkosti (AspectRatioContainer re-fit)
		hole_source.item_rect_changed.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if hole_source == null or not hole_source.is_visible_in_tree():
		draw_rect(full, dim_color)
		return
	var hole := (get_global_transform().affine_inverse() * hole_source.get_global_rect()) \
		.grow(hole_pad).intersection(full)
	# 4 pasy BEZ prekryvu — alpha sa v rohoch nesmie zdvojit
	var top := Rect2(0, 0, size.x, hole.position.y)
	var bottom := Rect2(0, hole.end.y, size.x, size.y - hole.end.y)
	var left := Rect2(0, hole.position.y, hole.position.x, hole.size.y)
	var right := Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y)
	for r in [top, bottom, left, right]:
		if r.has_area():
			draw_rect(r, dim_color)
