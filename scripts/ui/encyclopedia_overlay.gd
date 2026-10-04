extends Control
class_name EncyclopediaOverlay

# EncyclopediaOverlay — vsetci bohovia a karty jedneho panteonu, vlastnene
# aj zamknute. Tap na dlazdicu otvori CardFlashcard (detail + level up).
# Nic nemeni sama — level up ide cez flashcard -> PlayerProfile.upgrade_card().
# Rovnaky overlay pattern ako DeckOverlay (open()/close(), signal closed).

signal closed

@onready var owned_label: Label = $Panel/Margin/Content/Header/OwnedLabel
@onready var close_button: Button = $Panel/Margin/Content/Header/CloseButton
@onready var faction_tabs: HBoxContainer = $Panel/Margin/Content/FactionTabs
@onready var sections: VBoxContainer = $Panel/Margin/Content/Scroll/Sections
@onready var flashcard: CardFlashcard = $Flashcard

var _faction: StringName = &""

func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	PlayerProfile.profile_changed.connect(_on_profile_changed)

func open() -> void:
	for child in faction_tabs.get_children():
		child.queue_free()
	var factions := _collect_factions()
	var group := ButtonGroup.new()
	for faction in factions:
		var button := Button.new()
		button.text = String(faction).capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = faction == factions[0]
		button.pressed.connect(_select_faction.bind(faction))
		faction_tabs.add_child(button)
	_faction = factions[0] if not factions.is_empty() else &""
	_rebuild()
	visible = true

func close() -> void:
	if flashcard.visible:
		flashcard.close()
	visible = false
	closed.emit()

func _on_profile_changed() -> void:
	# level up za flashcardom -> dlazdica pod nim sa obnovi
	if visible:
		_rebuild()

func _select_faction(faction: StringName) -> void:
	_faction = faction
	_rebuild()

# Panteony = distinct faction cez vsetkych bohov a karty s obtain_source != 0.
func _collect_factions() -> Array[StringName]:
	var seen := {}
	for id in CardDB.list_hero_ids():
		seen[CardDB.get_hero(id).faction] = true
	for id in CardDB.list_card_ids():
		var card := CardDB.get_card(id)
		if card.obtain_source != 0:
			seen[card.faction] = true
	var factions: Array[StringName] = []
	factions.assign(seen.keys())
	factions.sort()
	return factions

# --- Stavba sekcii ---

func _rebuild() -> void:
	for child in sections.get_children():
		child.queue_free()

	var hero_ids: Array[StringName] = []
	for id in CardDB.list_hero_ids():
		if CardDB.get_hero(id).faction == _faction:
			hero_ids.append(id)

	var unit_ids: Array[StringName] = []
	var spell_ids: Array[StringName] = []
	for id in CardDB.list_card_ids():
		var card := CardDB.get_card(id)
		if card.obtain_source == 0 or card.faction != _faction:
			continue
		if card.unit_data != null:
			unit_ids.append(id)
		elif card.spell_data != null:
			spell_ids.append(id)
	unit_ids.sort_custom(_by_cost_then_id)
	spell_ids.sort_custom(_by_cost_then_id)

	_add_section("Gods", hero_ids, DeckTile.KIND_HERO)
	_add_section("Units", unit_ids, DeckTile.KIND_CARD)
	_add_section("Spells", spell_ids, DeckTile.KIND_CARD)

	var owned := 0
	for id in hero_ids:
		if PlayerProfile.owns_hero(id):
			owned += 1
	for id in unit_ids + spell_ids:
		if PlayerProfile.owns_card(id):
			owned += 1
	owned_label.text = "Owned %d / %d" % [owned, hero_ids.size() + unit_ids.size() + spell_ids.size()]

func _add_section(title: String, ids: Array[StringName], kind: StringName) -> void:
	if ids.is_empty():
		return
	var heading := Label.new()
	heading.text = title
	sections.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 8
	sections.add_child(grid)
	for id in ids:
		var tile := DeckTile.new()
		tile.setup(id, kind, -1)
		tile.interactive = true
		tile.allow_locked_tap = true
		tile.draggable = false
		tile.set_note(_note_for(id, kind))
		tile.tapped.connect(_on_tile_tapped)
		grid.add_child(tile)

func _note_for(id: StringName, kind: StringName) -> String:
	var owned := PlayerProfile.owns_hero(id) if kind == DeckTile.KIND_HERO else PlayerProfile.owns_card(id)
	if not owned:
		return ""
	if PlayerProfile.can_upgrade(id):
		return "Ready"
	var need := PlayerProfile.get_copies_to_next(id)
	if need < 0:
		return "MAX"
	var copies := PlayerProfile.get_hero_copies(id) if kind == DeckTile.KIND_HERO else PlayerProfile.get_card_copies(id)
	return "%d/%d" % [copies, need]

func _by_cost_then_id(a: StringName, b: StringName) -> bool:
	var cost_a := CardDB.get_card(a).cost
	var cost_b := CardDB.get_card(b).cost
	if cost_a != cost_b:
		return cost_a < cost_b
	return a < b

func _on_tile_tapped(tile: DeckTile) -> void:
	flashcard.open_for(tile.item_id, tile.kind)
