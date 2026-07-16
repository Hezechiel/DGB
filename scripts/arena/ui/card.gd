extends PanelContainer
class_name Card

# Rub sviktu — zdielany pre vsetky karty. Ak neskor pridu rubu podla frakcie
# alebo rarity, presunie sa toto do CardData.
const SCROLL_BACK: Texture2D = preload("res://assets/sprites/scrolls/scrolls_back.png")

@onready var scroll_icon: TextureRect = $VBoxContainer/MarginContainer/ScrollIcon
@onready var name_label: Label = $VBoxContainer/NameLabel

var card_data: CardData = null
var slot_index: int = -1   # nastavuje CardHand pri _ready()

func configure(data: CardData) -> void:
	card_data = data
	scroll_icon.texture = data.scroll_texture
	name_label.text = data.display_name

func clear() -> void:
	card_data = null
	scroll_icon.texture = null
	name_label.text = ""

# Otoc kartu na rub — volane pocas dragu ked je scroll nad mapou.
func show_back() -> void:
	scroll_icon.texture = SCROLL_BACK
	name_label.visible = false

# Vrat lic karty. Cita znovu z card_data — ziadny cachovany texture stav,
# takze sa to nemoze rozejst s configure().
func show_face() -> void:
	name_label.visible = true
	if card_data != null:
		scroll_icon.texture = card_data.scroll_texture

# Press na karte zacina drag. Dalsie eventy (drag/release) uz sleduje
# CardHand._input() podla touch indexu — nespoliehame sa na to, ci Godot
# posle ScreenDrag mimo rectu tejto karty do _gui_input.
func _gui_input(event: InputEvent) -> void:
	if card_data == null:
		return
	if event is InputEventScreenTouch and event.pressed:
		var hand := get_parent().get_parent().get_parent() as CardHand
		if hand != null:
			hand.begin_drag(slot_index, event.index)
		get_viewport().set_input_as_handled()
