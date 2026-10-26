@tool
extends Container
class_name WrapCardGrid

# WrapCardGrid — mriezka kariet s pevnym poctom stlpcov do VERTIKALNEHO scrollu.
# Sirka bunky = dostupna sirka / columns, vyska z cell_height_for_width
# (alebo card_aspect). Min. sirka je 0 (nikdy netlaci MainContent von),
# min. vyska = skutocna vyska riadkov (scroll vie, kolko obsahu ma).
# Neuplny posledny riadok je zarovnany VLAVO (encyklopedia, nie deck).
# Fixed-column grid whose height follows its width (for vertical scrolls).

@export var columns: int = 6:
	set(value):
		columns = maxi(1, value)
		_changed()
# sirka / vyska jednej karty (ked nie je cell_height_for_width)
@export var card_aspect: float = 0.82:
	set(value):
		card_aspect = maxf(0.05, value)
		_changed()
@export var h_separation: int = 8:
	set(value):
		h_separation = value
		_changed()
@export var v_separation: int = 8:
	set(value):
		v_separation = value
		_changed()

# func(width: float) -> float. Neplatny = width / card_aspect.
var cell_height_for_width: Callable

func _changed() -> void:
	queue_sort()
	update_minimum_size()

func _sorted_items() -> Array[Control]:
	var items: Array[Control] = []
	for child in get_children():
		var c := child as Control
		if c != null and c.visible and not c.top_level and not c.is_queued_for_deletion():
			items.append(c)
	return items

# Bunka pre aktualnu sirku. Prvy frame (size.x = 0) -> sirka 1, ziadne delenie nulou.
func _cell_size() -> Vector2:
	var w := maxf(1.0, (size.x - h_separation * (columns - 1)) / float(columns))
	var h := w / card_aspect
	if cell_height_for_width.is_valid():
		h = float(cell_height_for_width.call(w))
	return Vector2(w, maxf(1.0, h))

func _get_minimum_size() -> Vector2:
	var count := _sorted_items().size()
	if count <= 0:
		return Vector2.ZERO
	var rows := ceili(float(count) / float(columns))
	return Vector2(0.0, rows * _cell_size().y + (rows - 1) * v_separation)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_sort()
		NOTIFICATION_RESIZED:
			# vyska zavisi od sirky
			update_minimum_size()

func _sort() -> void:
	var items := _sorted_items()
	if items.is_empty():
		return
	var cell := _cell_size()
	for i in items.size():
		var r := floori(float(i) / float(columns))
		var c := i % columns
		var pos := Vector2(c * (cell.x + h_separation), r * (cell.y + v_separation))
		fit_child_in_rect(items[i], Rect2(pos.floor(), cell.floor()))
