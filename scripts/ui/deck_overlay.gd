extends Control
class_name DeckOverlay

# DeckOverlay — Deck obrazovka podla art dizajnu (main_menu_deck_building),
# vsetko pod sebou (Layout = VBox):
#   View mod (default po otvoreni tabu):
#     hore   velky boh (idle animacia aktivneho draft boha)
#     stred  panel balicka na celu sirku: logo panteonu + meno boha + synergy,
#            priemerny energy cost; 8 slotov (boh + 7 kariet) v JEDNOM riadku
#     dole   kratky bar len s tlacidlom Edit
#   Edit mod (tlacidlo Edit): boh sa skryje, panel balicka ide hore. Bar
#     ukaze CARD COLLECTION, filtre All / Units / Spells, hint a Cancel + Save;
#     pod barom kolekcia v 2 riadkoch, plnena po stlpcoch (horizontalny
#     scroll). Kolekcia ukazuje LEN karty (a bohov), ktore v drafte nie su;
#     po kazdej zmene draftu sa prestavi a znovu zoradi. Save / Cancel = spat
#     do View.
# Vsetko sa prisposobuje velkosti MainContent (FitCardGrid + vyska scrollu),
# ziadne pevne pixely kariet.
#
# Ovladanie: tap na kartu (oba mody, aj locked / forbidden) = Card Detail
# (signal card_detail_requested, otvara MainMenu). V Edit mode DRZANIE karty
# hold_to_drag_time sekund = drag na slot balicka (kratky tah prstom =
# scroll kolekcie). Ziadny tap-then-tap vyber. Edit mod zapina IBA tlacidlo Edit.
# Meni sa len lokalny draft — do profilu ide az cez Save
# (PlayerProfile.set_deck je jedine miesto, kde sa balicek realne uklada
# a zaroven robi boha aktivnym). Kazdy boh ma VLASTNY balicek: polozenie
# ineho boha na slot 0 nacita jeho balicek (alebo predvoleny); ak su v
# drafte neulozene zmeny kariet, opyta sa Discard / Cancel. Karty, ktore
# draft boh odmieta (DeckRules), su v kolekcii sede a "Forbidden".
# MainMenu tab page (activate()/deactivate()), rovnako ako ShopOverlay.
# Deck picker (Deck 1 / 2 / ...) z dizajnu zatial NIE je implementovany.

signal leave_confirmed   # hrac potvrdil Discard pri odchode z tabu
signal card_detail_requested(id: StringName, kind: StringName)

enum Filter { UNITS, SPELLS, ALL }

const HINT_TEXT := "Tap: details · hold %.0fs and drag onto the deck"
const NO_DECK_TEXT := "This god cannot field a full deck."
# sirka / vyska karty — art (s namalovanym ramom) ma pomer ~0.81–0.84,
# zobrazi sa cely (KEEP_ASPECT_CENTERED)
const CARD_ASPECT := 0.82
# Miesto pre horizontalny scrollbar pod kartami kolekcie.
const POOL_SCROLLBAR_SPACE := 12.0
# Kolekcia ma pevne 2 riadky, scroll je horizontalny.
const POOL_ROWS := 2
const POOL_V_SEPARATION := 6.0   # musi sediet s v_separation PoolGrid v scene
const TAB_ACTIVE_COLOR := Color(1.0, 0.85, 0.45)
const TAB_INACTIVE_COLOR := Color(0.7, 0.72, 0.78)
# Idle klip boha — obaja sucasni bohovia maju preklep "iddle_left".
const SHOWCASE_ANIMS: Array[StringName] = [&"iddle_left", &"idle_left"]

# Kolko sekund treba drzat kartu, kym sa zacne drag. Ladit podla pocitu.
@export var hold_to_drag_time: float = 1.0
# Idle animacie su "_left" — true otoci boha smerom ku kartam.
@export var showcase_flip_h: bool = false
# View mod: pomer vysky DeckPanel voci avataru boha (GodShowcase = 1.0).
@export var view_deck_ratio: float = 1.2
# Edit mod: pomer vysky CollectionPanel voci DeckPanel (DeckPanel = 1.0).
@export var edit_collection_ratio: float = 1.3

@onready var god_showcase: Control = %GodShowcase
@onready var god_sprite: AnimatedSprite2D = %GodSprite
@onready var god_art: TextureRect = %GodArt
@onready var pantheon_logo: TextureRect = %PantheonLogo
@onready var god_name_label: Label = %GodNameLabel
@onready var synergy_label: Label = %SynergyLabel
@onready var deck_panel: PanelContainer = %DeckPanel
@onready var collection_panel: PanelContainer = %CollectionPanel
@onready var collection_label: Label = %CollectionLabel
@onready var edit_button: Button = %EditButton
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton
@onready var avg_cost_label: Label = %AvgCostLabel
@onready var slot_grid: FitCardGrid = %SlotGrid
@onready var hint_label: Label = %HintLabel
@onready var units_tab: TextureButton = %UnitsTab
@onready var spells_tab: TextureButton = %SpellsTab
@onready var all_tab: TextureButton = %AllTab
@onready var pool_scroll: ScrollContainer = %PoolScroll
@onready var pool_grid: GridContainer = %PoolGrid

var _editing: bool = false
var _draft_hero: StringName = &""
var _draft_cards: Array[StringName] = []   # vzdy presne PlayerProfile.DECK_SIZE
var _discard_dialog: ConfirmationDialog
var _pending_hero: StringName = &""        # boh cakajuci na Discard
var _pending_leave: bool = false           # dialog je otvoreny kvoli odchodu z tabu (nie kvoli vymene boha)
var _filter: int = Filter.ALL
var _tab_buttons: Dictionary = {}          # Filter -> TextureButton
var _refresh_queued: bool = false

func _ready() -> void:
	visible = false
	slot_grid.card_aspect = CARD_ASPECT
	edit_button.pressed.connect(_on_edit_pressed)
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	pool_scroll.resized.connect(_resize_pool_tiles)
	god_showcase.resized.connect(_layout_showcase)
	PlayerProfile.profile_changed.connect(_on_profile_changed)

	_tab_buttons = {Filter.UNITS: units_tab, Filter.SPELLS: spells_tab, Filter.ALL: all_tab}
	var group := ButtonGroup.new()
	for f in _tab_buttons:
		var tab: TextureButton = _tab_buttons[f]
		tab.toggle_mode = true
		tab.button_group = group
		tab.pressed.connect(_set_filter.bind(f))
	_tab_buttons[_filter].button_pressed = true
	_update_tab_labels()

	# Ziadna Save moznost v dialogu — ukladat sa da len hlavnym Save.
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.dialog_text = "Unsaved changes to this deck will be lost."
	_discard_dialog.ok_button_text = "Discard"
	_discard_dialog.cancel_button_text = "Cancel"
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	_discard_dialog.canceled.connect(_on_discard_canceled)
	add_child(_discard_dialog)

func activate() -> void:
	_load_draft()
	_set_editing(false)
	_refresh_draft_view()   # prestavi aj kolekciu — az po nacitani draftu
	visible = true

func deactivate() -> void:
	if _editing:
		_load_draft()
		_set_editing(false)
		_refresh_draft_view()
	visible = false

# Neulozene zmeny pri odchode z tabu: karty ALEBO iny draft boh ako aktivny.
func has_unsaved_changes() -> bool:
	return _editing and (_has_unsaved_card_changes() or _draft_hero != PlayerProfile.get_deck_hero())

# MainMenu vola pri pokuse prepnut tab, ked has_unsaved_changes() == true.
func confirm_leave() -> void:
	_pending_hero = &""
	_pending_leave = true
	_discard_dialog.popup_centered()

func _load_draft() -> void:
	_draft_hero = PlayerProfile.get_deck_hero()
	_draft_cards = PlayerProfile.get_deck_cards()

# Prepina View / Edit layout (okamzite, bez animacie). Edit zapina IBA
# tlacidlo Edit; vo View su sloty mrtve (ziadny tap, ziadny drag).
func _set_editing(value: bool) -> void:
	_editing = value
	god_showcase.visible = not value
	edit_button.visible = not value
	save_button.visible = value
	cancel_button.visible = value
	collection_label.visible = value
	for tab in [all_tab, units_tab, spells_tab]:
		(tab as Control).visible = value
	hint_label.text = HINT_TEXT % hold_to_drag_time
	hint_label.visible = value
	pool_scroll.visible = value
	if value:
		pool_scroll.scroll_horizontal = 0
		deck_panel.size_flags_stretch_ratio = 1.0
		collection_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		collection_panel.size_flags_stretch_ratio = edit_collection_ratio
	else:
		# kolekcia bez expand -> panel sa stiahne na vysku baru
		deck_panel.size_flags_stretch_ratio = view_deck_ratio
		collection_panel.size_flags_vertical = Control.SIZE_FILL
	for child in slot_grid.get_children():
		var tile := child as DeckCardTile
		if tile != null:
			tile.draggable = value

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
		_pending_leave = false
		_discard_dialog.popup_centered()
		return
	_switch_hero(id, deck)

func _on_discard_confirmed() -> void:
	if _pending_leave:
		_pending_leave = false
		deactivate()
		leave_confirmed.emit()
		return
	if _pending_hero == &"":
		return
	var id := _pending_hero
	_pending_hero = &""
	_switch_hero(id, PlayerProfile.get_deck_for(id))

func _on_discard_canceled() -> void:
	_pending_leave = false
	_pending_hero = &""

func _switch_hero(id: StringName, deck: Array[StringName]) -> void:
	_draft_hero = id
	_draft_cards = deck
	hint_label.text = HINT_TEXT % hold_to_drag_time
	_queue_refresh()

func _on_edit_pressed() -> void:
	_set_editing(true)

func _on_save_pressed() -> void:
	if PlayerProfile.set_deck(_draft_hero, _draft_cards):
		_set_editing(false)
		_refresh_draft_view()
	else:
		push_warning("DeckOverlay: set_deck odmietol draft %s / %s" % [_draft_hero, _draft_cards])

func _on_cancel_pressed() -> void:
	_load_draft()
	_set_editing(false)
	_refresh_draft_view()

# Profil sa zmenil (Save, F10 grant, upgrade...) — levely/kopie v kolekcii.
# Rozpracovany draft sa neprepisuje.
func _on_profile_changed() -> void:
	if not visible:
		return
	if not _editing:
		_load_draft()
	_refresh_draft_view()

# --- Filtre kolekcie ---

func _set_filter(f: int) -> void:
	if f == _filter:
		return
	_filter = f
	_update_tab_labels()
	_rebuild_pool()
	pool_scroll.scroll_horizontal = 0

func _update_tab_labels() -> void:
	for f in _tab_buttons:
		var label := (_tab_buttons[f] as Control).get_node_or_null("Label") as Label
		if label != null:
			label.add_theme_color_override("font_color", TAB_ACTIVE_COLOR if f == _filter else TAB_INACTIVE_COLOR)

# --- Stavba ---

# Zmeny draftu sa prekreslia odlozene: tap/drop prichadza z _gui_input /
# _drop_data samotnej karty, ktoru by sme inak mazali pocas jej callbacku.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()

func _deferred_refresh() -> void:
	_refresh_queued = false
	_refresh_draft_view()

# Sloty + kolekcia (bez kariet z draftu, znovu zoradena) + hlavicka podla
# draftu. Horizontalny scroll kolekcie ostava — nastavi sa naspat odlozene,
# az ked sa mriezka znovu rozlozi.
func _refresh_draft_view() -> void:
	_rebuild_slots()
	var scroll_x := pool_scroll.scroll_horizontal
	_rebuild_pool()
	_restore_pool_scroll.call_deferred(scroll_x)
	_update_header()
	_update_showcase()

func _restore_pool_scroll(scroll_x: int) -> void:
	pool_scroll.scroll_horizontal = scroll_x

func _rebuild_slots() -> void:
	_free_children(slot_grid)
	slot_grid.add_child(_make_tile(_draft_hero, DeckTile.KIND_HERO, 0, false))
	var slot := 1
	for id in _draft_cards:
		slot_grid.add_child(_make_tile(id, DeckTile.KIND_CARD, slot, false))
		slot += 1

func _rebuild_pool() -> void:
	_free_children(pool_grid)
	var tiles: Array[Control] = []
	if _filter == Filter.ALL:
		for id in _pool_hero_ids():
			tiles.append(_make_tile(id, DeckTile.KIND_HERO, -1, true))
	for id in _pool_card_ids():
		tiles.append(_make_tile(id, DeckTile.KIND_CARD, -1, true))

	# GridContainer plni po RIADKOCH — indexy preratame tak, aby poradie islo
	# po STLPCOCH (hore, dole, dalsi stlpec) a citalo sa zlava doprava v paroch.
	# Pri neparnom pocte drzi filler spodnu bunku posledneho stlpca, inak by
	# sa horny riadok posunul. Column-major order in a row-major grid.
	var cols := maxi(1, ceili(float(tiles.size()) / POOL_ROWS))
	pool_grid.columns = cols
	var cells: Array[Control] = []
	cells.resize(POOL_ROWS * cols)
	for i in tiles.size():
		cells[(i % POOL_ROWS) * cols + floori(float(i) / POOL_ROWS)] = tiles[i]
	for cell in cells:
		var node := cell
		if node == null:
			node = Control.new()
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pool_grid.add_child(node)
	_resize_pool_tiles()
	_refresh_pool_states()

func _refresh_pool_states() -> void:
	for child in pool_grid.get_children():
		var tile := child as DeckCardTile
		if tile == null:
			continue
		# karty z draftu v kolekcii nie su -> "IN DECK" uz nikdy
		if tile.kind == DeckTile.KIND_HERO:
			tile.set_state(false, false)
		else:
			var forbidden := PlayerProfile.owns_card(tile.item_id) and not _is_allowed(tile.item_id)
			tile.set_state(false, forbidden)

# Vyska kolekcie je dana scrollom (zvysok obrazovky), delena na POOL_ROWS
# riadkov — sirka z pomeru karty. Aj fillery, aby mriezka drzala tvar.
func _resize_pool_tiles() -> void:
	var avail := pool_scroll.size.y - POOL_SCROLLBAR_SPACE - POOL_V_SEPARATION * (POOL_ROWS - 1)
	var h := maxf(40.0, avail / POOL_ROWS)
	var w := DeckCardTile.width_for_height(h, CARD_ASPECT, true)
	for child in pool_grid.get_children():
		(child as Control).custom_minimum_size = Vector2(w, h)

func _free_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _make_tile(id: StringName, kind: StringName, slot: int, in_pool: bool) -> DeckCardTile:
	var tile := DeckCardTile.new()
	tile.show_progress = in_pool
	tile.hold_to_drag_time = hold_to_drag_time
	if slot >= 0:
		tile.draggable = _editing   # sloty sa daju tahat len v Edit mode
	tile.setup(id, kind, slot)
	tile.tapped.connect(_on_tile_tapped)
	if slot >= 0:
		tile.dropped.connect(_on_tile_dropped)
	return tile

func _update_header() -> void:
	var hero: HeroData = CardDB.get_hero(_draft_hero) if CardDB.has_hero(_draft_hero) else null
	god_name_label.text = hero.display_name.to_upper() if hero != null else String(_draft_hero)
	pantheon_logo.texture = DeckCardTile.logo_for(hero.faction) if hero != null else null
	_update_synergy_label(hero)

	var total := 0
	var count := 0
	for id in _draft_cards:
		if CardDB.has_card(id):
			total += CardDB.get_card(id).cost
			count += 1
	avg_cost_label.text = "%.1f" % (float(total) / count) if count > 0 else "—"

# Synergy prah draft boha s live poctom (napr. "Olympus 2 / 4"). Rovnaky text
# ako HUD tooltip (DeckRules.describe_synergy). Zlaty = splnene, sedy = nie.
func _update_synergy_label(hero: HeroData) -> void:
	if hero == null or DeckRules.describe_synergy(hero) == "":
		synergy_label.text = ""
		synergy_label.tooltip_text = ""
		return
	var cards: Array[CardData] = []
	for id in _draft_cards:
		if CardDB.has_card(id):
			cards.append(CardDB.get_card(id))
	var have := DeckRules.count_synergy_cards(hero, cards)
	var active := DeckRules.is_synergy_active(hero, cards)
	synergy_label.text = "Synergy — %s %d / %d · %s" % [String(hero.synergy_tag).capitalize(),
		have, hero.synergy_count, DeckRules.describe_synergy(hero)]
	synergy_label.tooltip_text = synergy_label.text
	synergy_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if active else Color(0.62, 0.64, 0.7))

# --- Boh vlavo ---
# Idle animacia draft boha (rovnako ako showcase v HomeView). Boh bez idle
# klipu -> card_art ako obrazok. Shared SpriteFrames sa len priradi.

func _update_showcase() -> void:
	var hero: HeroData = CardDB.get_hero(_draft_hero) if CardDB.has_hero(_draft_hero) else null
	var frames: SpriteFrames = hero.sprite_frames if hero != null else null
	var anim := _find_idle_anim(frames)
	if anim != &"":
		god_art.visible = false
		god_sprite.visible = true
		god_sprite.flip_h = showcase_flip_h
		if god_sprite.sprite_frames != frames or god_sprite.animation != anim or not god_sprite.is_playing():
			god_sprite.sprite_frames = frames
			god_sprite.play(anim)
	else:
		god_sprite.visible = false
		god_sprite.stop()
		god_art.texture = hero.card_art if hero != null else null
		god_art.visible = god_art.texture != null
	_layout_showcase()

func _find_idle_anim(frames: SpriteFrames) -> StringName:
	if frames == null:
		return &""
	for anim in SHOWCASE_ANIMS:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			return anim
	return &""

# Node2D v Control sa neprisposobuje sam — vycentrujeme a zmensime rucne.
func _layout_showcase() -> void:
	var area := god_showcase.size
	god_sprite.position = area * 0.5
	if god_sprite.sprite_frames == null or not god_sprite.sprite_frames.has_animation(god_sprite.animation):
		return
	var tex := god_sprite.sprite_frames.get_frame_texture(god_sprite.animation, 0)
	if tex == null or area.x <= 0.0 or area.y <= 0.0:
		return
	var fs := tex.get_size()
	var s := minf(area.x / fs.x, area.y / fs.y)
	god_sprite.scale = Vector2(s, s)

# --- Poradie kolekcie ---

# Bez aktualneho draft boha. Vlastnene najprv, potom zamknute; v ramci
# skupiny podla id.
func _pool_hero_ids() -> Array[StringName]:
	var ids := CardDB.list_hero_ids()
	ids.erase(_draft_hero)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var owned_a := PlayerProfile.owns_hero(a)
		var owned_b := PlayerProfile.owns_hero(b)
		if owned_a != owned_b:
			return owned_a
		return a < b
	)
	return ids

# Bez testovacich kariet (obtain_source == 0) a bez kariet z draftu, podla
# aktivneho filtra. Vlastnene najprv, potom zamknute; v ramci skupiny podla
# cost, potom id.
func _pool_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in CardDB.list_card_ids():
		var card := CardDB.get_card(id)
		if card.obtain_source == 0:
			continue
		if _draft_cards.has(id):
			continue
		if _filter == Filter.UNITS and card.unit_data == null:
			continue
		if _filter == Filter.SPELLS and card.spell_data == null:
			continue
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

# Tap = Card Detail v oboch modoch (draft ani mod sa nemenia).
func _on_tile_tapped(tile: DeckCardTile) -> void:
	card_detail_requested.emit(tile.item_id, tile.kind)

func _on_tile_dropped(source: Dictionary, target: DeckCardTile) -> void:
	if not _editing:
		return
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
			return true   # nic na zmenu
		# iny boh = iny balicek; _request_hero_switch sam prekresli (alebo nie)
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
	_queue_refresh()
	return true
