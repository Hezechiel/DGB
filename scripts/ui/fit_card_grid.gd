@tool
extends Container
class_name FitCardGrid

# FitCardGrid — mriezka kariet, ktora sa VZDY zmesti do svojho priestoru.
# Velkost karty sa pocita z dostupnej sirky aj vysky (mensia z nich vyhra),
# pri zachovani pomeru stran card_aspect. Neuplny posledny riadok je
# vycentrovany (5 + 4 ako v art dizajne). Minimalna velkost je 0, takze
# kontajner nikdy netlaci layout MainContent von z obrazovky — karty sa
# radsej zmensia.
# Card grid that shrinks/grows its cells to fit, keeping the card aspect.

@export var columns: int = 5:
	set(value):
		columns = maxi(1, value)
		queue_sort()
# sirka / vyska jednej karty
@export var card_aspect: float = 0.82:
	set(value):
		card_aspect = maxf(0.05, value)
		queue_sort()
@export var h_separation: int = 8:
	set(value):
		h_separation = value
		queue_sort()
@export var v_separation: int = 8:
	set(value):
		v_separation = value
		queue_sort()
# 0 = bez limitu. Na sirokych obrazovkach karty inak rastu do obrovskych rozmerov.
@export var max_card_width: float = 0.0:
	set(value):
		max_card_width = value
		queue_sort()

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort()

func _sorted_items() -> Array[Control]:
	var items: Array[Control] = []
	for child in get_children():
		var c := child as Control
		if c != null and c.visible and not c.top_level and not c.is_queued_for_deletion():
			items.append(c)
	return items

# Velkost jednej bunky pre aktualnu velkost kontajnera.
func get_card_size() -> Vector2:
	return _card_size(_sorted_items().size())

func _card_size(count: int) -> Vector2:
	if count <= 0:
		return Vector2.ZERO
	var rows := ceili(float(count) / float(columns))
	var w_by_width := (size.x - h_separation * (columns - 1)) / float(columns)
	var h_by_height := (size.y - v_separation * (rows - 1)) / float(rows)
	var w := minf(w_by_width, h_by_height * card_aspect)
	if max_card_width > 0.0:
		w = minf(w, max_card_width)
	w = maxf(w, 1.0)
	return Vector2(w, w / card_aspect)

func _sort() -> void:
	var items := _sorted_items()
	if items.is_empty():
		return
	var cell := _card_size(items.size())
	var rows := ceili(float(items.size()) / float(columns))
	var total_h := rows * cell.y + (rows - 1) * v_separation
	var y0 := (size.y - total_h) * 0.5
	for r in rows:
		var start := r * columns
		var count := mini(columns, items.size() - start)
		var row_w := count * cell.x + (count - 1) * h_separation
		var x0 := (size.x - row_w) * 0.5
		for i in count:
			var pos := Vector2(x0 + i * (cell.x + h_separation), y0 + r * (cell.y + v_separation))
			fit_child_in_rect(items[start + i], Rect2(pos.floor(), cell.floor()))
