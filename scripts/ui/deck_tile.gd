extends PanelContainer
class_name DeckTile

# DeckTile — jedna dlazdica (boh alebo karta). Pouziva sa v Deck obrazovke
# (8 slotov balicka aj pool) a v Encyklopedii. Sama NIC nemeni — len hlasi
# tap a drag&drop cez signaly/callbacky; logiku drzi DeckOverlay /
# EncyclopediaOverlay.

signal tapped(tile: DeckTile)
# Emitovany na CIELOVEJ dlazdici, ked na nu nieco pustia.
signal dropped(source: Dictionary, target: DeckTile)

const KIND_HERO := &"hero"
const KIND_CARD := &"card"
const TILE_SIZE := Vector2(124, 150)
# Tap sa uzna len ked prst skonci blizko miesta stlacenia (scroll poolu != tap).
const TAP_MAX_DISTANCE := 10.0
const SELECTED_TINT := Color(1.0, 0.85, 0.35)

var item_id: StringName = &""
var kind: StringName = KIND_CARD
var slot_index: int = -1      # 0 = boh, 1..7 = karty, -1 = dlazdica v poole
var locked: bool = false      # nevlastnene — sede, neda sa vybrat ani tahat
var interactive: bool = false # false mimo edit modu
var allow_locked_tap: bool = false # encyklopedia: aj zamknuta dlazdica sa da tapnut
var draggable: bool = true    # encyklopedia: ziadny drag

var _picture: TextureRect
var _name_label: Label
var _info_label: Label
var _base_info: String = ""
var _press_pos: Vector2 = Vector2.ZERO
var _pressed: bool = false

func _init() -> void:
	custom_minimum_size = TILE_SIZE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_picture)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)

	_info_label = Label.new()
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_info_label)

func setup(id: StringName, tile_kind: StringName, slot: int) -> void:
	item_id = id
	kind = tile_kind
	slot_index = slot
	_picture.texture = null
	_name_label.text = String(id)

	if kind == KIND_HERO:
		locked = not PlayerProfile.owns_hero(id)
		var hero: HeroData = CardDB.get_hero(id) if CardDB.has_hero(id) else null
		if hero != null:
			_name_label.text = hero.display_name
			_picture.texture = _hero_texture(hero)
		_base_info = "God · Locked" if locked else "God · Lv %d" % PlayerProfile.get_hero_level(id)
	else:
		locked = not PlayerProfile.owns_card(id)
		var card: CardData = CardDB.get_card(id) if CardDB.has_card(id) else null
		var cost := 0
		if card != null:
			_name_label.text = card.display_name
			_picture.texture = card.scroll_texture
			cost = card.cost
		if locked:
			_base_info = "Cost %d · Locked" % cost
		else:
			_base_info = "Cost %d · Lv %d" % [cost, PlayerProfile.get_card_level(id)]

	_info_label.text = _base_info
	modulate = Color(0.45, 0.45, 0.45) if locked else Color.WHITE

func set_selected(value: bool) -> void:
	self_modulate = SELECTED_TINT if value else Color.WHITE

# Len pre pool dlazdice — text sa sklada vzdy znova z _base_info.
func set_in_deck(value: bool) -> void:
	_info_label.text = _base_info + (" · In deck" if value else "")

# Volitelna poznamka za zakladnym textom (napr. "3/4", "Ready", "MAX").
func set_note(text: String) -> void:
	_info_label.text = _base_info + (" · " + text if text != "" else "")

# Karta, ktoru aktualny boh odmieta: seda, neda sa vybrat ani tahat.
func set_forbidden() -> void:
	locked = true
	modulate = Color(0.45, 0.45, 0.45)
	set_note("Forbidden")

# Prvy frame idle animacie; obaja sucasni bohovia maju preklep "iddle_left".
func _hero_texture(hero: HeroData) -> Texture2D:
	var frames := hero.sprite_frames
	if frames == null:
		return null
	for anim in [&"iddle_left", &"idle_left"]:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			return frames.get_frame_texture(anim, 0)
	return null

# Len mouse eventy — emulate_touch_from_mouse + default mouse-from-touch
# pokryju desktop aj dotyk. ScreenTouch NEchytat, inak by tap padol 2x.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_pos = event.position
		_pressed = true
		return
	if not _pressed:
		return
	_pressed = false
	if interactive and (not locked or allow_locked_tap) and event.position.distance_to(_press_pos) <= TAP_MAX_DISTANCE:
		tapped.emit(self)

func _get_drag_data(_pos: Vector2) -> Variant:
	if not interactive or not draggable or locked or item_id == &"":
		return null
	_pressed = false
	var preview := Label.new()
	preview.text = _name_label.text
	set_drag_preview(preview)
	return {"id": item_id, "kind": kind, "from_slot": slot_index}

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not interactive or slot_index < 0:
		return false
	if not (data is Dictionary) or not data.has("kind"):
		return false
	if slot_index == 0:
		return data["kind"] == KIND_HERO
	return data["kind"] == KIND_CARD

func _drop_data(_pos: Vector2, data: Variant) -> void:
	dropped.emit(data, self)
