extends Control
class_name FilterChip

# FilterChip — tapnutelny "chip" filtra (ALL, panteon, typ karty, Owned).
# Sam NIC nefiltruje — len hlasi tap; stav (active) nastavuje vlastnik.
# Vlastna detekcia tapu namiesto TextureButton: chip moze byt v horizontalnom
# ScrollContainer — swipe musi posuvat zoznam, nie prepinat chip.
# Tap-only toggle chip; the owner decides what "active" means.

signal tapped(chip: FilterChip)

const TEX_ACTIVE := preload("res://assets/menu/deck/tab_active.png")
const TEX_INACTIVE := preload("res://assets/menu/deck/tab_inactive.png")
const TAB_ACTIVE_COLOR := Color(1.0, 0.85, 0.45)
const TAB_INACTIVE_COLOR := Color(0.7, 0.72, 0.78)
const TAP_MAX_DISTANCE := 10.0
const PADDING := 24.0
const ICON_GAP := 4.0

@export var font_size: int = 13:
	set(value):
		font_size = value
		if _label != null:
			_label.add_theme_font_size_override("font_size", font_size)
			update_minimum_size()

# Payload vlastnika (napr. faction alebo typ filtra).
var key: StringName = &""
var active: bool = false:
	set(value):
		active = value
		_apply_active()

var _bg: TextureRect
var _box: HBoxContainer
var _icon: TextureRect
var _label: Label

var _pressed: bool = false
var _press_pos: Vector2 = Vector2.ZERO

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS  # PASS: scroll rodica dostane tah prstom

	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_box = HBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", int(ICON_GAP))
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_box)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	_box.add_child(_icon)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 3)
	_box.add_child(_label)

	_apply_active()

func setup(text: String, icon: Texture2D = null) -> void:
	_label.text = text
	_icon.texture = icon
	_icon.visible = icon != null
	_layout_icon()
	update_minimum_size()

func _apply_active() -> void:
	if _bg == null:
		return
	_bg.texture = TEX_ACTIVE if active else TEX_INACTIVE
	_label.add_theme_color_override("font_color", TAB_ACTIVE_COLOR if active else TAB_INACTIVE_COLOR)

# Ikona je stvorec podla vysky chipu (nie podla textury).
func _icon_side() -> float:
	return maxf(0.0, maxf(size.y, custom_minimum_size.y) - 8.0)

func _layout_icon() -> void:
	var side := _icon_side()
	_icon.custom_minimum_size = Vector2(side, side)

func _get_minimum_size() -> Vector2:
	var w := PADDING
	if _label != null:
		w += _label.get_minimum_size().x
	if _icon != null and _icon.visible:
		w += _icon_side() + ICON_GAP
	return Vector2(w, custom_minimum_size.y)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			if _icon != null:
				_layout_icon()
		NOTIFICATION_MOUSE_EXIT:
			_pressed = false  # scroll ukradol tah — ziadny zaseknuty stav

# --- Vstup ---
# Len mouse eventy (emulate touch pokryje dotyk). ScreenTouch NEchytat,
# inak by tap padol 2x.

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _pressed and event.position.distance_to(_press_pos) > TAP_MAX_DISTANCE:
			_pressed = false
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_pressed = true
		_press_pos = event.position
		return
	if not _pressed:
		return
	_pressed = false
	if event.position.distance_to(_press_pos) <= TAP_MAX_DISTANCE:
		tapped.emit(self)
