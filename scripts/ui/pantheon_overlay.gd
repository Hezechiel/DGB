extends Control
class_name PantheonOverlay

# PantheonOverlay — encyklopedia panteonov: vsetci bohovia a karty, vlastnene
# aj zamknute. Tri ramovane bloky pod sebou:
#   HeaderPanel   — emblem, nazov, celkovy pocet vlastnenych (bez filtrov)
#   PantheonPanel — fixny ALL chip + horizontalne posuvny rad panteonov (multi-select)
#   MainPanel     — filtre (typ karty, Owned only) + vertikalny scroll sekcii;
#                   sekcia = jeden panteon, zbalena = prvy riadok, rozbalena = vsetko
# Stav filtrov a rozbalenia je len pre session (v pamati, neuklada sa).
# Ziadny kontajner nema velku min. sirku — stranka sa vzdy zmesti do MainContent.
# Tap na dlazdicu otvori CardDetail (detail + level up) cez card_detail_requested.
# Nic nemeni sama — level up ide cez CardDetail -> PlayerProfile.upgrade_card().
# MainMenu tab page (activate()/deactivate()), rovnako ako DeckOverlay.

signal card_detail_requested(id: StringName, kind: StringName)

enum TypeFilter { ALL, GODS, UNITS, SPELLS }

const CARD_ASPECT := 0.82          # rovnako ako deck_overlay.gd
const TAP_MAX_DISTANCE := 10.0
const CHIP_HEIGHT := 30.0
const GOLD := Color(1.0, 0.8, 0.35)
const TYPE_CHIPS := [
	[TypeFilter.ALL, "ALL"],
	[TypeFilter.GODS, "GODS"],
	[TypeFilter.UNITS, "UNITS"],
	[TypeFilter.SPELLS, "SPELLS"],
]
const FRAME_TEX := preload("res://assets/menu/deck/frame_ninepatchrect.png")

@export var columns: int = 6       # karty v riadku (zbaleny panteon = 1 riadok)

@onready var total_owned_label: Label = %TotalOwnedLabel
@onready var all_chip_holder: Control = %AllChipHolder
@onready var pantheon_chips: HBoxContainer = %PantheonChips
@onready var type_chips: HBoxContainer = %TypeChips
@onready var owned_chip_holder: Control = %OwnedChipHolder
@onready var sections_scroll: ScrollContainer = %SectionsScroll
@onready var sections: VBoxContainer = %Sections
@onready var empty_label: Label = %EmptyLabel

var _selected: Dictionary = {}     # faction -> true; PRAZDNE = ALL (vsetky panteony)
var _type_filter: int = TypeFilter.ALL
var _owned_only: bool = false
var _expanded: Dictionary = {}     # faction -> bool

var _all_chip: FilterChip
var _owned_chip: FilterChip
var _rebuild_queued: bool = false
var _keep_scroll: bool = false
var _dirty: bool = false           # profil sa zmenil, kym bola stranka skryta (CardDetail)
var _header_press: Dictionary = {} # header -> pozicia stlacenia

func _ready() -> void:
	visible = false
	_all_chip = _make_chip("ALL", null, &"")
	_all_chip.tapped.connect(_on_all_tapped)
	_fill_holder(all_chip_holder, _all_chip)
	for entry in TYPE_CHIPS:
		var chip := _make_chip(entry[1], null, StringName(str(entry[0])))
		chip.tapped.connect(_on_type_tapped.bind(int(entry[0])))
		type_chips.add_child(chip)
	_owned_chip = _make_chip("OWNED ONLY", null, &"owned")
	_owned_chip.tapped.connect(_on_owned_tapped)
	_fill_holder(owned_chip_holder, _owned_chip)
	PlayerProfile.profile_changed.connect(_on_profile_changed)

func activate() -> void:
	_rebuild_pantheon_chips()
	_refresh_chips()
	_rebuild()
	visible = true

func deactivate() -> void:
	visible = false

func _on_profile_changed() -> void:
	# level up za CardDetailom -> dlazdica pod nim sa obnovi
	if not visible:
		return
	if is_visible_in_tree():
		_queue_rebuild(true)
	else:
		# MainContent je skryty (CardDetail) — layout nebezi, scroll by sa
		# orezal na 0. Prestavba az ked je stranka znovu vidiet.
		_dirty = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _dirty and is_visible_in_tree():
		_dirty = false
		_queue_rebuild(true)

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

# --- Chipy ---

func _make_chip(text: String, icon: Texture2D, chip_key: StringName) -> FilterChip:
	var chip := FilterChip.new()
	chip.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	chip.key = chip_key
	chip.setup(text, icon)
	return chip

func _fill_holder(holder: Control, chip: FilterChip) -> void:
	holder.add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# Panteony sa menia len s novymi datami — staci raz za activate().
func _rebuild_pantheon_chips() -> void:
	_free_children(pantheon_chips)
	for faction in _collect_factions():
		var chip := _make_chip(String(faction).to_upper(), DeckCardTile.logo_for(faction), faction)
		chip.tapped.connect(_on_pantheon_tapped)
		pantheon_chips.add_child(chip)

func _refresh_chips() -> void:
	_all_chip.active = _selected.is_empty()
	for chip in pantheon_chips.get_children():
		chip.active = _selected.has(chip.key)
	var i := 0
	for chip in type_chips.get_children():
		chip.active = int(TYPE_CHIPS[i][0]) == _type_filter
		i += 1
	_owned_chip.active = _owned_only

func _on_all_tapped(_chip: FilterChip) -> void:
	_selected.clear()
	_filters_changed()

func _on_pantheon_tapped(chip: FilterChip) -> void:
	if _selected.has(chip.key):
		_selected.erase(chip.key)   # prazdna mnozina = znovu ALL
	else:
		_selected[chip.key] = true
	_filters_changed()

func _on_type_tapped(_chip: FilterChip, filter: int) -> void:
	_type_filter = filter
	_filters_changed()

func _on_owned_tapped(_chip: FilterChip) -> void:
	_owned_only = not _owned_only
	_filters_changed()

func _filters_changed() -> void:
	_refresh_chips()
	sections_scroll.scroll_vertical = 0
	_queue_rebuild(false)

# --- Polozky a pocty ---

# [[id, kind], ...] panteonu po filtroch: bohovia (podla id), jednotky, kuzla.
func _items_for(faction: StringName) -> Array:
	var items: Array = []
	if _type_filter == TypeFilter.ALL or _type_filter == TypeFilter.GODS:
		var hero_ids: Array[StringName] = []
		for id in CardDB.list_hero_ids():
			if CardDB.get_hero(id).faction == faction and (not _owned_only or PlayerProfile.owns_hero(id)):
				hero_ids.append(id)
		hero_ids.sort()
		for id in hero_ids:
			items.append([id, DeckTile.KIND_HERO])
	if _type_filter == TypeFilter.GODS:
		return items

	var unit_ids: Array[StringName] = []
	var spell_ids: Array[StringName] = []
	for id in CardDB.list_card_ids():
		var card := CardDB.get_card(id)
		if card.obtain_source == 0 or card.faction != faction:
			continue
		if _owned_only and not PlayerProfile.owns_card(id):
			continue
		if card.unit_data != null:
			unit_ids.append(id)
		elif card.spell_data != null:
			spell_ids.append(id)
	unit_ids.sort_custom(_by_cost_then_id)
	spell_ids.sort_custom(_by_cost_then_id)
	if _type_filter != TypeFilter.SPELLS:
		for id in unit_ids:
			items.append([id, DeckTile.KIND_CARD])
	if _type_filter != TypeFilter.UNITS:
		for id in spell_ids:
			items.append([id, DeckTile.KIND_CARD])
	return items

# Vector2i(owned, total) celeho panteonu — ignoruje filtre (stabilny progres).
func _pantheon_counts(faction: StringName) -> Vector2i:
	var owned := 0
	var total := 0
	for id in CardDB.list_hero_ids():
		if CardDB.get_hero(id).faction == faction:
			total += 1
			if PlayerProfile.owns_hero(id):
				owned += 1
	for id in CardDB.list_card_ids():
		var card := CardDB.get_card(id)
		if card.obtain_source != 0 and card.faction == faction:
			total += 1
			if PlayerProfile.owns_card(id):
				owned += 1
	return Vector2i(owned, total)

func _by_cost_then_id(a: StringName, b: StringName) -> bool:
	var cost_a := CardDB.get_card(a).cost
	var cost_b := CardDB.get_card(b).cost
	if cost_a != cost_b:
		return cost_a < cost_b
	return a < b

# --- Stavba sekcii ---

# Tap prichadza z _gui_input chipu / hlavicky, ktoru by sme inak mazali
# pocas jej callbacku — prestavba ide odlozene.
func _queue_rebuild(keep_scroll: bool) -> void:
	_keep_scroll = _keep_scroll or keep_scroll
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()

func _deferred_rebuild() -> void:
	_rebuild_queued = false
	var keep := _keep_scroll
	_keep_scroll = false
	var scroll_y := sections_scroll.scroll_vertical
	_rebuild()
	if keep:
		_restore_scroll(scroll_y)

# WrapCardGrid potrebuje jeden layout frame (resize -> min. vyska), az potom
# ma scroll spravny rozsah.
func _restore_scroll(scroll_y: int) -> void:
	await get_tree().process_frame
	sections_scroll.scroll_vertical = scroll_y

func _rebuild() -> void:
	_free_children(sections)
	_header_press.clear()

	var shown: Array = []   # [[faction, items], ...]
	var owned_total := Vector2i.ZERO
	for faction in _collect_factions():
		owned_total += _pantheon_counts(faction)
		if not _selected.is_empty() and not _selected.has(faction):
			continue
		var items := _items_for(faction)
		if not items.is_empty():
			shown.append([faction, items])

	# jediny viditelny panteon sa ukaze cely bez dalsieho tapu
	var forced := shown.size() == 1
	for entry in shown:
		sections.add_child(_build_section(entry[0], entry[1], forced))

	sections_scroll.visible = not shown.is_empty()
	empty_label.visible = shown.is_empty()
	total_owned_label.text = "%d / %d" % [owned_total.x, owned_total.y]

func _build_section(faction: StringName, items: Array, forced: bool) -> Control:
	var can_toggle := not forced and items.size() > columns
	var expanded := forced or bool(_expanded.get(faction, false))

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var frame := ScaledNinePatch.new()
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.texture = FRAME_TEX
	frame.patch_margin_left = 52
	frame.patch_margin_top = 46
	frame.patch_margin_right = 52
	frame.patch_margin_bottom = 46
	frame.patch_scale = 0.45
	frame.fill_color = Color(0.08, 0.10, 0.16, 0.9)
	frame.fill_inset = 3.0
	panel.add_child(frame)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	box.add_child(_build_section_header(faction, expanded, can_toggle))

	var grid := WrapCardGrid.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = columns
	grid.card_aspect = CARD_ASPECT
	grid.cell_height_for_width = func(w: float) -> float:
		return DeckCardTile.height_for_width(w, CARD_ASPECT, true)
	box.add_child(grid)

	var count := items.size() if expanded else mini(columns, items.size())
	for i in count:
		var tile := DeckCardTile.new()
		tile.show_progress = true
		tile.draggable = false
		tile.setup(items[i][0], items[i][1], -1)
		tile.tapped.connect(_on_tile_tapped)
		grid.add_child(tile)
	return panel

func _build_section_header(faction: StringName, expanded: bool, can_toggle: bool) -> Control:
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(0, 32)
	header.mouse_filter = Control.MOUSE_FILTER_PASS  # PASS: swipe po hlavicke scrolluje
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	header.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	header.add_child(hbox)

	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(28, 28)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.texture = DeckCardTile.logo_for(faction)
	logo.visible = logo.texture != null
	hbox.add_child(logo)

	var name_label := _make_header_label("%s PANTHEON" % String(faction).to_upper(), 16, GOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_label)

	var counts := _pantheon_counts(faction)
	hbox.add_child(_make_header_label("%d / %d" % [counts.x, counts.y], 14, Color(0.85, 0.85, 0.9)))

	var chevron := _make_header_label("▼" if expanded else "▶", 14, GOLD)
	chevron.visible = can_toggle
	hbox.add_child(chevron)

	if can_toggle:
		header.gui_input.connect(_on_section_header_input.bind(faction, header))
	return header

func _make_header_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0))
	label.add_theme_constant_override("outline_size", 4)
	return label

# Vlastna detekcia tapu (rovnake pravidlo ako DeckCardTile) — Button v scrolle
# by zjedol swipe alebo sa spustil po nom. Len mouse eventy, nie ScreenTouch.
func _on_section_header_input(event: InputEvent, faction: StringName, header: Control) -> void:
	if event is InputEventMouseMotion:
		if _header_press.has(header) and event.position.distance_to(_header_press[header]) > TAP_MAX_DISTANCE:
			_header_press.erase(header)
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_header_press[header] = event.position
		return
	if not _header_press.has(header):
		return
	var is_tap: bool = event.position.distance_to(_header_press[header]) <= TAP_MAX_DISTANCE
	_header_press.erase(header)
	if is_tap:
		_expanded[faction] = not bool(_expanded.get(faction, false))
		_queue_rebuild(true)

func _on_tile_tapped(tile: DeckCardTile) -> void:
	card_detail_requested.emit(tile.item_id, tile.kind)

func _free_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
