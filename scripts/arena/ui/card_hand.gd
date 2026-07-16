extends Panel
class_name CardHand

# PLACEHOLDER: mana cost checks are added in a later step.

# arena.gd pocuva a riadi DeployGhost (CardHand je v CanvasLayer, ghost je
# world-space Node2D — rovnaky pattern ako HUD signaly)
signal deploy_preview_updated(world_pos: Vector2, is_valid: bool)
signal deploy_preview_ended

@export var deck: Array[CardData] = []

@onready var card_1: Card = $MarginContainer/HBoxContainer/Card1
@onready var card_2: Card = $MarginContainer/HBoxContainer/Card2
@onready var card_3: Card = $MarginContainer/HBoxContainer/Card3
@onready var next_card_preview: Card = $MarginContainer/HBoxContainer/NextCardPreview

var _slots: Array[Card] = []
var _cycle: Array[CardData] = [] # fronta kariet — zahrana karta ide na koniec (Clash Royale styl)

var _drag_slot: int = -1
var _drag_touch_index: int = -1
var _drag_showing_back: bool = false

func _ready() -> void:
	_slots = [card_1, card_2, card_3]

	# skopiruj a zamiesaj balicek do cyklickej fronty
	_cycle = deck.duplicate()
	randomize()
	_cycle.shuffle()

	for i in _slots.size():
		_slots[i].slot_index = i
		_slots[i].configure(_cycle.pop_front())
	_update_preview()

func _update_preview() -> void:
	if _cycle.is_empty():
		next_card_preview.clear()
	else:
		next_card_preview.configure(_cycle[0])

# Volane z Card._gui_input pri presse.
func begin_drag(slot_index: int, touch_index: int) -> void:
	if slot_index < 0 or slot_index >= _slots.size():
		return
	if _slots[slot_index].card_data == null:
		return
	_drag_slot = slot_index
	_drag_touch_index = touch_index
	_drag_showing_back = false

# Drag a release sledujeme v _input() (bezi PRED GUI aj pred _unhandled_input),
# takze eventy nikdy nedojdu do arena_camera.gd (pan) ani arena.gd (tap-to-move).
# Preto tu NEPOUZIVAME InputR.suppress_next_release() — release si konzumujeme sami.
func _input(event: InputEvent) -> void:
	if _drag_touch_index == -1:
		return
	if event is InputEventScreenDrag and event.index == _drag_touch_index:
		var world_pos := _screen_to_world(event.position)
		deploy_preview_updated.emit(world_pos, BattleManager.is_deploy_position_valid(world_pos, "player"))
		# Nad rukou = chysta sa zrusenie, ukaz lic. Mimo ruky (nad mapou) = rub.
		var over_hand := get_global_rect().has_point(event.position)
		if over_hand and _drag_showing_back:
			_slots[_drag_slot].show_face()
			_drag_showing_back = false
		elif not over_hand and not _drag_showing_back:
			_slots[_drag_slot].show_back()
			_drag_showing_back = true
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed and event.index == _drag_touch_index:
		_finish_drag(event.position)
		get_viewport().set_input_as_handled()

# CardHand je v CanvasLayer (HUD) — get_canvas_transform() by tu vratilo
# transform vrstvy, nie kamery. Preto ide cez viewport.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _finish_drag(screen_pos: Vector2) -> void:
	var slot := _drag_slot
	_drag_slot = -1
	_drag_touch_index = -1
	# Lic sa vracia vzdy a na jednom mieste — pri uspesnom zahrani ho play_card()
	# aj tak hned prepise cez configure() novou kartou (rovnaky frame, bez bliknutia).
	if _drag_showing_back:
		_slots[slot].show_face()
		_drag_showing_back = false
	deploy_preview_ended.emit()
	# release nad samotnou rukou = zrusenie (aj obycajny tap na kartu bez pohybu)
	if get_global_rect().has_point(screen_pos):
		return
	var world_pos := _screen_to_world(screen_pos)
	if not BattleManager.is_deploy_position_valid(world_pos, "player"):
		return   # neplatne miesto — karta zostava v ruke, nic sa nespawnuje
	play_card(slot, world_pos)

# Jediny entry point pre zahranie karty (buduce double-tap a network handler
# ho tiez budu volat).
func play_card(slot_index: int, world_pos: Vector2) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot := _slots[slot_index]
	var played_data := slot.card_data
	if played_data == null:
		return false
	BattleManager.spawn_unit(played_data.id, world_pos, "player")
	_cycle.push_back(played_data) # zahrana karta ide na koniec fronty
	slot.configure(_cycle.pop_front()) # slot sa doplni z frontu
	_update_preview()
	return true

# Panel absorbuje vsetky tapy vo svojej ploche, aby neprepadli do
# arena.gd tap-to-move (mouse_filter=STOP tu nestaci — release rovnakeho
# tapnutia by aj tak dosiel do _unhandled_input, preto suppress_next_release).
# Toto pokryva tapy na pozadi panelu — karty samotne uz event skonzumuju
# vo vlastnom _gui_input.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		InputR.suppress_next_release()
	get_viewport().set_input_as_handled()
