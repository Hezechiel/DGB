extends Control
class_name DeckOverlay

# DeckOverlay — Deck obrazovka (SWFA styl): 8 slotov = boh vlavo + 7 kariet.
# Edit mod ukaze pool bohov a kariet; hrac ich klada do slotov drag&dropom
# alebo tap-then-tap. Meni sa len lokalny draft — do profilu ide az cez Save
# (PlayerProfile.set_deck je jedine miesto, kde sa balicek realne uklada
# a zaroven robi boha aktivnym). Kazdy boh ma VLASTNY balicek: polozenie
# ineho boha na slot 0 nacita jeho balicek (alebo predvoleny); ak su v
# drafte neulozene zmeny kariet, opyta sa Discard / Cancel. Karty, ktore
# draft boh odmieta (DeckRules), su v poole sede a "Forbidden".
# Rovnaky overlay pattern ako ShopOverlay (open()/close(), signal closed).

signal closed

const HINT_TEXT := "Drag a scroll onto a slot, or tap a scroll and then a slot."
const NO_DECK_TEXT := "This god cannot field a full deck."

@onready var edit_button: Button = $DeckPanel/Margin/Content/Header/EditButton
@onready var save_button: Button = $DeckPanel/Margin/Content/Header/SaveButton
@onready var cancel_button: Button = $DeckPanel/Margin/Content/Header/CancelButton
@onready var close_button: Button = $DeckPanel/Margin/Content/Header/CloseButton
@onready var slot_row: HBoxContainer = $DeckPanel/Margin/Content/SlotRow
@onready var hint_label: Label = $DeckPanel/Margin/Content/HintLabel
@onready var pool_scroll: ScrollContainer = $DeckPanel/Margin/Content/PoolScroll
@onready var pool_grid: GridContainer = $DeckPanel/Margin/Content/PoolScroll/PoolGrid

var _editing: bool = false
var _draft_hero: StringName = &""
var _draft_cards: Array[StringName] = []   # vzdy presne PlayerProfile.DECK_SIZE
var _selected: DeckTile = null             # tap-then-tap vyber
var _discard_dialog: ConfirmationDialog
var _pending_hero: StringName = &""        # boh cakajuci na Discard

func _ready() -> void:
	visible = false
	hint_label.text = HINT_TEXT
	edit_button.pressed.connect(_on_edit_pressed)
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	close_button.pressed.connect(close)

	# Ziadna Save moznost v dialogu — ukladat sa da len hlavnym Save.
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.dialog_text = "Unsaved changes to this deck will be lost."
	_discard_dialog.ok_button_text = "Discard"
	_discard_dialog.cancel_button_text = "Cancel"
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	add_child(_discard_dialog)

func open() -> void:
	_load_draft()
	_set_editing(false)
	visible = true

func close() -> void:
	if _editing:
		_load_draft()
		_set_editing(false)
	visible = false
	closed.emit()

func _load_draft() -> void:
	_draft_hero = PlayerProfile.get_deck_hero()
	_draft_cards = PlayerProfile.get_deck_cards()

func _set_editing(value: bool) -> void:
	_editing = value
	edit_button.visible = not value
	save_button.visible = value
	cancel_button.visible = value
	hint_label.visible = value
	hint_label.text = HINT_TEXT
	pool_scroll.visible = value
	_rebuild()

# Neulozene zmeny KARIET aktualneho draft boha (samotna vymena boha sa nerata).
func _has_unsaved_card_changes() -> bool:
	return _draft_cards != PlayerProfile.get_deck_for(_draft_hero)

func _request_hero_switch(id: StringName) -> void:
	var deck := PlayerProfile.get_deck_for(id)
	if deck.size() != PlayerProfile.DECK_SIZE:
		push_error("DeckOverlay: boh '%s' nema plny balicek (%d/%d) — chyba obsahu" % [id, deck.size(), PlayerProfile.DECK_SIZE])
		hint_label.text = NO_DECK_TEXT
		return
	if _has_unsaved_card_changes():
		_pending_hero = id
		_discard_dialog.popup_centered()
		return
	_switch_hero(id, deck)

func _on_discard_confirmed() -> void:
	if _pending_hero == &"":
		return
	var id := _pending_hero
	_pending_hero = &""
	_switch_hero(id, PlayerProfile.get_deck_for(id))

func _switch_hero(id: StringName, deck: Array[StringName]) -> void:
	_draft_hero = id
	_draft_cards = deck
	hint_label.text = HINT_TEXT
	# _rebuild() zaroven zrusi vyber
	_rebuild()

func _on_edit_pressed() -> void:
	_set_editing(true)

func _on_save_pressed() -> void:
	if PlayerProfile.set_deck(_draft_hero, _draft_cards):
		_set_editing(false)
	else:
		push_warning("DeckOverlay: set_deck odmietol draft %s / %s" % [_draft_hero, _draft_cards])

func _on_cancel_pressed() -> void:
	_load_draft()
	_set_editing(false)

# --- Stavba dlazdic ---

func _rebuild() -> void:
	# vyber ukazuje na dlazdicu, ktora sa ide zmazat
	_selected = null
	for child in slot_row.get_children():
		child.queue_free()
	for child in pool_grid.get_children():
		child.queue_free()

	slot_row.add_child(_make_tile(_draft_hero, DeckTile.KIND_HERO, 0))
	var slot := 1
	for id in _draft_cards:
		slot_row.add_child(_make_tile(id, DeckTile.KIND_CARD, slot))
		slot += 1

	if not _editing:
		return
	for id in _pool_hero_ids():
		var tile := _make_tile(id, DeckTile.KIND_HERO, -1)
		tile.set_in_deck(id == _draft_hero)
		pool_grid.add_child(tile)
	for id in _pool_card_ids():
		var tile := _make_tile(id, DeckTile.KIND_CARD, -1)
		tile.set_in_deck(_draft_cards.has(id))
		if PlayerProfile.owns_card(id) and not _is_allowed(id):
			tile.set_forbidden()
		pool_grid.add_child(tile)

func _make_tile(id: StringName, kind: StringName, slot: int) -> DeckTile:
	var tile := DeckTile.new()
	tile.setup(id, kind, slot)
	tile.interactive = _editing
	tile.tapped.connect(_on_tile_tapped)
	if slot >= 0:
		tile.dropped.connect(_on_tile_dropped)
	return tile

# Vlastnene najprv, potom zamknute; v ramci skupiny podla id.
func _pool_hero_ids() -> Array[StringName]:
	var ids := CardDB.list_hero_ids()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var owned_a := PlayerProfile.owns_hero(a)
		var owned_b := PlayerProfile.owns_hero(b)
		if owned_a != owned_b:
			return owned_a
		return a < b
	)
	return ids

# Bez testovacich kariet (obtain_source == 0). Vlastnene najprv, potom
# zamknute; v ramci skupiny podla cost, potom id.
func _pool_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in CardDB.list_card_ids():
		if CardDB.get_card(id).obtain_source != 0:
			ids.append(id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var owned_a := PlayerProfile.owns_card(a)
		var owned_b := PlayerProfile.owns_card(b)
		if owned_a != owned_b:
			return owned_a
		var cost_a := CardDB.get_card(a).cost
		var cost_b := CardDB.get_card(b).cost
		if cost_a != cost_b:
			return cost_a < cost_b
		return a < b
	)
	return ids

# Smie draft boh mat tuto kartu? (DeckRules — boh proti karte)
func _is_allowed(card_id: StringName) -> bool:
	if not CardDB.has_hero(_draft_hero) or not CardDB.has_card(card_id):
		return false
	return DeckRules.is_card_allowed(CardDB.get_hero(_draft_hero), CardDB.get_card(card_id))

# --- Vstup ---

func _on_tile_tapped(tile: DeckTile) -> void:
	if tile == _selected:
		tile.set_selected(false)
		_selected = null
		return
	if _selected != null and tile.slot_index >= 0:
		if _place(_selected.item_id, _selected.kind, tile.slot_index):
			return
	# novy vyber (aj ked umiestnenie nesedelo — napr. boh na slot karty)
	if _selected != null:
		_selected.set_selected(false)
	_selected = tile
	tile.set_selected(true)

func _on_tile_dropped(source: Dictionary, target: DeckTile) -> void:
	_place(source["id"], source["kind"], target.slot_index)

# Jedine miesto, kde sa meni draft. kind musi sediet so slotom (0 = boh).
# Karta, ktora UZ je v drafte na inom slote, sa s cielovym slotom VYMENI —
# draft tak nikdy neobsahuje duplikat ani prazdny slot.
# Vracia true ak sa draft zmenil (alebo ostal rovnaky po platnom umiestneni).
func _place(id: StringName, kind: StringName, to_slot: int) -> bool:
	if to_slot == 0:
		if kind != DeckTile.KIND_HERO or not PlayerProfile.owns_hero(id):
			return false
		if id == _draft_hero:
			# nic na zmenu — len zrus vyber
			_rebuild()
			return true
		# iny boh = iny balicek; _request_hero_switch sam rebuildne (alebo nie)
		_request_hero_switch(id)
		return true
	elif to_slot >= 1 and to_slot <= PlayerProfile.DECK_SIZE:
		if kind != DeckTile.KIND_CARD or not PlayerProfile.owns_card(id):
			return false
		if not _is_allowed(id):
			return false
		var target := to_slot - 1
		var j := _draft_cards.find(id)
		if j >= 0:
			_draft_cards[j] = _draft_cards[target]
			_draft_cards[target] = id
		else:
			_draft_cards[target] = id
	else:
		return false
	_rebuild()
	return true
