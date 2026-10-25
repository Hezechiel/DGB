@tool
extends Control
class_name ScaledNinePatch

# ScaledNinePatch — NinePatchRect, ktory vie patche (rohy/okraje) aj ZMENSIT.
# Obycajny NinePatchRect kresli rohy vzdy v plnej velkosti textury, takze ked
# je karta mensia ako patch_margin_left + right, ornamenty sa prekryju a ram sa
# zdeformuje. Tu sa cela textura najprv zmensi faktorom (auto podla velkosti
# controlu, alebo pevny patch_scale) a az potom sa stredne pasy natiahnu.
# Rohy si tak drzia pomer stran a ram vyzera rovnako na velkej aj malej karte.
# Nine-patch whose corner/edge patches scale down with the control size.

@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var patch_margin_left: int = 0:
	set(value):
		patch_margin_left = value
		queue_redraw()
@export var patch_margin_top: int = 0:
	set(value):
		patch_margin_top = value
		queue_redraw()
@export var patch_margin_right: int = 0:
	set(value):
		patch_margin_right = value
		queue_redraw()
@export var patch_margin_bottom: int = 0:
	set(value):
		patch_margin_bottom = value
		queue_redraw()
# 0 = auto: textura sa zmensi tak, aby sa zmestila do controlu (nikdy sa
# nezvacsuje nad 1.0). > 0 = pevny faktor (stale obmedzeny tak, aby sa
# protilahle patche neprekryli).
@export_range(0.0, 4.0, 0.01) var patch_scale: float = 0.0:
	set(value):
		patch_scale = value
		queue_redraw()
@export var draw_center: bool = false:
	set(value):
		draw_center = value
		queue_redraw()
# Vypln POD ramom (napr. tmave pozadie panelu). Alfa 0 = nic sa nekresli.
@export var fill_color: Color = Color(0, 0, 0, 0):
	set(value):
		fill_color = value
		queue_redraw()
# Odsadenie vyplne od okraja v px ZDROJOVEJ textury (skaluje sa ako patche),
# aby vypln nevytrcala spod vonkajsieho okraja ramu.
@export var fill_inset: float = 0.0:
	set(value):
		fill_inset = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

# Faktor, ktorym sa kreslia patche. Pouziva aj DeckCardTile na odsadenie artu.
func get_effective_scale() -> float:
	if texture == null:
		return 1.0
	var tex := texture.get_size()
	var s := patch_scale
	if s <= 0.0:
		s = minf(1.0, minf(size.x / tex.x, size.y / tex.y))
	var mx := float(patch_margin_left + patch_margin_right)
	var my := float(patch_margin_top + patch_margin_bottom)
	if mx > 0.0:
		s = minf(s, size.x / mx)
	if my > 0.0:
		s = minf(s, size.y / my)
	return maxf(s, 0.0)

func _draw() -> void:
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var tex := texture.get_size()
	var s := get_effective_scale()
	if fill_color.a > 0.0:
		var fill := Rect2(Vector2.ONE * fill_inset * s, size - Vector2.ONE * 2.0 * fill_inset * s)
		if fill.size.x > 0.0 and fill.size.y > 0.0:
			draw_rect(fill, fill_color)
	var l := float(patch_margin_left)
	var t := float(patch_margin_top)
	var r := float(patch_margin_right)
	var b := float(patch_margin_bottom)
	var src_x := PackedFloat32Array([0.0, l, tex.x - r, tex.x])
	var src_y := PackedFloat32Array([0.0, t, tex.y - b, tex.y])
	var dst_x := PackedFloat32Array([0.0, l * s, size.x - r * s, size.x])
	var dst_y := PackedFloat32Array([0.0, t * s, size.y - b * s, size.y])
	for iy in 3:
		for ix in 3:
			if ix == 1 and iy == 1 and not draw_center:
				continue
			var src := Rect2(src_x[ix], src_y[iy], src_x[ix + 1] - src_x[ix], src_y[iy + 1] - src_y[iy])
			var dst := Rect2(dst_x[ix], dst_y[iy], dst_x[ix + 1] - dst_x[ix], dst_y[iy + 1] - dst_y[iy])
			if src.size.x <= 0.0 or src.size.y <= 0.0 or dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			draw_texture_rect_region(texture, dst, src)
