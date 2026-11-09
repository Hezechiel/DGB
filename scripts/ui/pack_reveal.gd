extends PanelContainer
class_name PackReveal

# PackReveal — ramovany vysledok otvoreneho balicka / relikviara: titulok, horizontalny
# zoznam kariet (NEW / +1 copy) a OK. Pouziva Shop, neskor aj Rewards tab.
# Len zobrazuje — losovanie, NEW vypocet a grant robi volajuci.
# Tap na kartu -> card_detail_requested (volajuci ho preposle do MainMenu).

signal closed
signal card_detail_requested(id: StringName, kind: StringName)

const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Unique"]
const TAP_MAX_DISTANCE := 10.0     # rovnako ako DeckCardTile / Pantheon

@onready var title_label: Label = %RevealTitle
@onready var list: HBoxContainer = %RevealList
@onready var ok_button: Button = %RevealOkButton

var _press: Dictionary = {}  # entry -> pozicia stlacenia

func _ready() -> void:
	ok_button.pressed.connect(_on_ok_pressed)

# Prazdne ids -> "Nothing to reveal" (rovnako ako doteraz v Shope).
func show_result(title: String, ids: Array[StringName], is_new: Array[bool]) -> void:
	for child in list.get_children():
		child.queue_free()
	_press.clear()
	for i in ids.size():
		list.add_child(_build_entry(ids[i], is_new[i] if i < is_new.size() else false))
	title_label.text = title if not ids.is_empty() else "Nothing to reveal"
	visible = true

# Len skryje; closed NEemituje (to robi iba OK).
func hide_reveal() -> void:
	visible = false

func _on_ok_pressed() -> void:
	hide_reveal()
	closed.emit()

func _build_entry(id: StringName, is_new: bool) -> Control:
	var display_name := String(id)
	var rarity := 0
	var texture: Texture2D = null
	var kind := &""
	if CardDB.has_card(id):
		var card := CardDB.get_card(id)
		display_name = card.display_name
		rarity = card.rarity
		texture = card.scroll_texture
		kind = DeckTile.KIND_CARD
	elif CardDB.has_hero(id):
		# bohovia zatial nemaju scroll art — obrazok ostane prazdny
		var hero := CardDB.get_hero(id)
		display_name = hero.display_name
		rarity = hero.rarity
		kind = DeckTile.KIND_HERO

	var entry := VBoxContainer.new()
	# PASS: swipe po entry stale scrolluje RevealScroll; tap riesi _on_entry_input
	entry.mouse_filter = Control.MOUSE_FILTER_PASS
	if kind != &"":
		entry.gui_input.connect(_on_entry_input.bind(id, kind, entry))
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.custom_minimum_size = Vector2(120, 144)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = texture
	entry.add_child(picture)

	var name_label := Label.new()
	name_label.text = display_name
	entry.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.text = RARITY_NAMES[rarity] if rarity >= 0 and rarity < RARITY_NAMES.size() else "?"
	entry.add_child(rarity_label)

	var status_label := Label.new()
	status_label.text = "NEW" if is_new else "+1 copy"
	entry.add_child(status_label)
	return entry

# Vlastna detekcia tapu (rovnake pravidlo ako Pantheon hlavicka) — Button v scrolle
# by zjedol swipe alebo sa spustil po nom. Len mouse eventy, nie ScreenTouch.
func _on_entry_input(event: InputEvent, id: StringName, kind: StringName, entry: Control) -> void:
	if event is InputEventMouseMotion:
		if _press.has(entry) and event.position.distance_to(_press[entry]) > TAP_MAX_DISTANCE:
			_press.erase(entry)
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press[entry] = event.position
		return
	if not _press.has(entry):
		return
	var is_tap: bool = event.position.distance_to(_press[entry]) <= TAP_MAX_DISTANCE
	_press.erase(entry)
	if is_tap:
		card_detail_requested.emit(id, kind)
