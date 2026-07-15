extends PanelContainer
class_name Card

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
