extends Panel
class_name CardHand

# PLACEHOLDER: mana cost checks and drag-to-deploy wiring are added in a
# later step.

@export var deck: Array[CardData] = []

@onready var card_1: Card = $MarginContainer/HBoxContainer/Card1
@onready var card_2: Card = $MarginContainer/HBoxContainer/Card2
@onready var card_3: Card = $MarginContainer/HBoxContainer/Card3
@onready var next_card_preview: Card = $MarginContainer/HBoxContainer/NextCardPreview

var _slots: Array[Card] = []
var _cycle: Array[CardData] = [] # fronta kariet — zahrana karta ide na koniec (Clash Royale styl)

func _ready() -> void:
	_slots = [card_1, card_2, card_3]

	# skopiruj a zamiesaj balicek do cyklickej fronty
	_cycle = deck.duplicate()
	randomize()
	_cycle.shuffle()

	for slot in _slots:
		slot.configure(_cycle.pop_front())
	_update_preview()

func _update_preview() -> void:
	if _cycle.is_empty():
		next_card_preview.clear()
	else:
		next_card_preview.configure(_cycle[0])

# Volane ked hrac zahra kartu zo slotu — zatial nenapojene na ziadny input;
# buduca drag-to-deploy logika bude volat tuto funkciu ako jediny vstupny bod.
func play_card(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	var slot := _slots[slot_index]
	var played_data := slot.card_data
	if played_data == null:
		return
	_cycle.push_back(played_data) # zahrana karta ide na koniec fronty
	slot.configure(_cycle.pop_front()) # slot sa doplni z frontu
	_update_preview()

# Panel absorbuje vsetky tapy vo svojej ploche, aby neprepadli do
# arena.gd tap-to-move (mouse_filter=STOP tu nestaci — release rovnakeho
# tapnutia by aj tak dosiel do _unhandled_input, preto suppress_next_release).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		InputR.suppress_next_release()
	get_viewport().set_input_as_handled()
