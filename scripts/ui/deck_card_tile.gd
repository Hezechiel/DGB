extends Control
class_name DeckCardTile

# DeckCardTile — karta v Deck obrazovke (sloty balicka aj Card Collection).
# Art karty ma vlastny namalovany ram — zobrazi sa CELY (keep aspect, bez
# orezu). Dlazdica cez neho len kresli overlay: cost badge vlavo hore, velke
# logo panteonu v pravom dolnom rohu (cast vytrca cez okraj karty a je
# orezana), nad nim "Lv. N" vpravo dole, status (IN DECK / LOCKED /
# FORBIDDEN) a volitelne progres kopii pod kartou (len v kolekcii). Vsetky rozmery sa pocitaju
# z aktualnej velkosti — kartu len natiahne/zmensi rodicovsky kontajner.
#
# Vstup (gesta):
#   tap      — kazda karta (aj locked / forbidden) -> signal tapped (Card Detail)
#   swipe    — scroll kolekcie (pohyb > TAP_MAX_DISTANCE zrusi tap aj drzanie)
#   DRZANIE  — hold_to_drag_time sekund na vlastnenej, povolenej karte, len ked
#              draggable (= Edit mod): glow sa "nabija", potom sa karta zdvihne —
#              jej miesto ostane prazdne a plna kopia karty ide za prstom.
#              Pustenie mimo platneho slotu = zrusene, karta sa vrati.
# Ziadny tap-then-tap vyber — glow je len feedback drzania. Sama NIC nemeni —
# len hlasi cez signaly; logiku drzi DeckOverlay. Pantheon tab (encyklopedia)
# pouziva tiez DeckCardTile (nedragovatelny, s progres barom); KIND_* konstanty
# su stale v DeckTile.

signal tapped(tile: DeckCardTile)
# Emitovany na CIELOVEJ karte, ked na nu nieco pustia.
signal dropped(source: Dictionary, target: DeckCardTile)
# Drzanie sa naplnilo a zacal drag.
signal hold_drag_started(tile: DeckCardTile)

# Logo panteonu podla konvencie nazvu: logo_greek.png, logo_norse.png, ...
# Novy panteon = len novy obrazok, ziadna zmena kodu.
const LOGO_PATH := "res://assets/menu/logos/logo_%s.png"

const TAP_MAX_DISTANCE := 10.0
# Kym neubehne tento cas, drzanie sa vizualne neprejavuje (bezny tap neblika).
const HOLD_FEEDBACK_DELAY := 0.15
# Podiel vysky dlazdice pre progres bar (len show_progress).
const BAR_RATIO := 0.14
const BAR_GAP := 3.0
# Logo panteonu v pravom dolnom rohu — vacsie, cast vytrca cez okraj karty
# a je orezana (_logo_clip). Ladit podla artu.
const LOGO_SIZE := 0.5        # sirka loga ako podiel sirky karty
const LOGO_OVERHANG := 0.25   # podiel loga, ktory vytrca vpravo aj dole (orezane)
# Hrubka obrysu "Lv. N" ako podiel velkosti fontu — citatelne aj nad logom.
const LEVEL_OUTLINE_RATIO := 0.45

const GOLD := Color(1.0, 0.82, 0.35)
const DIM := Color(0.42, 0.42, 0.42)
const BAR_READY := Color(0.28, 0.72, 0.22)
const BAR_NORMAL := Color(0.2, 0.5, 0.9)

static var _logo_cache: Dictionary = {}

var item_id: StringName = &""
var kind: StringName = DeckTile.KIND_CARD
var slot_index: int = -1      # 0 = boh, 1..7 = karty, -1 = karta v kolekcii
var locked: bool = false      # nevlastnene
var forbidden: bool = false   # draft boh kartu odmieta
var in_deck: bool = false     # len kolekcia: karta uz je v drafte
var draggable: bool = true
var show_progress: bool = false
var hold_to_drag_time: float = 2.0

var _glow: Panel
var _outline: Panel
var _art_clip: Control
var _art: TextureRect
var _cost_badge: Panel
var _cost_label: Label
var _logo_clip: Control
var _logo: TextureRect
var _level_label: Label
var _status_label: Label
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _bar_label: Label

var _pressed: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _hold_elapsed: float = 0.0
var _dragging: bool = false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS  # PASS: scroll kolekcie dostane tah prstom
	# Art (~1150 px) a logo (~1400 px) sa tu zmensuju 10x+ — Linear + mipmapy,
	# inak zrnia (projekt ma default Nearest). Mipmapy treba zapnut v Import
	# docku PNG; bez nich je to len Linear.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)

	_glow = Panel.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_sb := StyleBoxFlat.new()
	glow_sb.bg_color = Color(GOLD, 0.35)
	glow_sb.border_color = GOLD
	glow_sb.set_border_width_all(3)
	glow_sb.set_corner_radius_all(8)
	glow_sb.shadow_color = Color(GOLD, 0.75)
	glow_sb.shadow_size = 10
	_glow.add_theme_stylebox_override("panel", glow_sb)
	_glow.visible = false
	add_child(_glow)

	_art_clip = Control.new()
	_art_clip.clip_contents = true
	_art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_clip)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_clip.add_child(_art)

	# Logo hned nad artom (pod level labelom); clip ho oreze na okraji karty.
	_logo_clip = Control.new()
	_logo_clip.clip_contents = true
	_logo_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo_clip)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_clip.add_child(_logo)

	# Obrys NAD artom — glow pod kartou v kolekcii orezava scroll, obrys nie.
	_outline = Panel.new()
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_sb := StyleBoxFlat.new()
	outline_sb.draw_center = false
	outline_sb.border_color = GOLD
	outline_sb.set_border_width_all(3)
	outline_sb.set_corner_radius_all(6)
	_outline.add_theme_stylebox_override("panel", outline_sb)
	_outline.visible = false
	add_child(_outline)

	_status_label = _make_label(4)
	var status_sb := StyleBoxFlat.new()
	status_sb.bg_color = Color(0, 0, 0, 0.6)
	status_sb.set_corner_radius_all(3)
	_status_label.add_theme_stylebox_override("normal", status_sb)

	_level_label = _make_label(4)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_cost_badge = Panel.new()
	_cost_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost_sb := StyleBoxFlat.new()
	cost_sb.bg_color = Color(0.13, 0.32, 0.78)
	cost_sb.border_color = Color(0.85, 0.9, 1.0)
	cost_sb.set_border_width_all(2)
	cost_sb.set_corner_radius_all(64)
	_cost_badge.add_theme_stylebox_override("panel", cost_sb)
	add_child(_cost_badge)
	_cost_label = _make_label(4)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.07, 0.12, 0.9)
	bar_bg.border_color = Color(0.55, 0.45, 0.25)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = BAR_NORMAL
	_bar_fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	_bar.visible = false
	add_child(_bar)
	_bar_label = _make_label(3)
	_bar_label.visible = false

func _make_label(outline: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	add_child(label)
	return label

# Logo panteonu (cache). null = panteon zatial nema logo -> badge sa skryje.
static func logo_for(faction: StringName) -> Texture2D:
	if faction == &"":
		return null
	if _logo_cache.has(faction):
		return _logo_cache[faction]
	var path := LOGO_PATH % faction
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_logo_cache[faction] = tex
	return tex

# Sirka dlazdice pre danu vysku (kolekcia ma vysku danu scrollom).
static func width_for_height(height: float, card_aspect: float, with_progress: bool) -> float:
	var card_h := height
	if with_progress:
		card_h = height * (1.0 - BAR_RATIO) - BAR_GAP
	return maxf(1.0, card_h * card_aspect)

# Vyska dlazdice pre danu sirku — inverzia width_for_height (WrapCardGrid
# v encyklopedii ma sirku danu stlpcami).
static func height_for_width(width: float, card_aspect: float, with_progress: bool) -> float:
	var card_h := width / card_aspect
	if with_progress:
		return maxf(1.0, (card_h + BAR_GAP) / (1.0 - BAR_RATIO))
	return maxf(1.0, card_h)

func setup(id: StringName, tile_kind: StringName, slot: int) -> void:
	item_id = id
	kind = tile_kind
	slot_index = slot
	var tex: Texture2D = null
	var faction: StringName = &""
	var cost := -1
	var level := 0
	var copies := 0
	tooltip_text = String(id)

	if kind == DeckTile.KIND_HERO:
		locked = not PlayerProfile.owns_hero(id)
		var hero: HeroData = CardDB.get_hero(id) if CardDB.has_hero(id) else null
		if hero != null:
			tex = _hero_texture(hero)
			faction = hero.faction
			tooltip_text = hero.display_name
		level = PlayerProfile.get_hero_level(id)
		copies = PlayerProfile.get_hero_copies(id)
	else:
		locked = not PlayerProfile.owns_card(id)
		var card: CardData = CardDB.get_card(id) if CardDB.has_card(id) else null
		if card != null:
			tex = card.scroll_texture
			faction = card.faction
			cost = card.cost
			tooltip_text = card.display_name
		level = PlayerProfile.get_card_level(id)
		copies = PlayerProfile.get_card_copies(id)

	_art.texture = tex
	_cost_badge.visible = cost >= 0
	_cost_label.visible = cost >= 0
	_cost_label.text = str(cost)
	_logo.texture = logo_for(faction)
	_logo.visible = _logo.texture != null
	_logo_clip.visible = _logo.texture != null
	_level_label.text = "" if locked else "Lv. %d" % level

	_bar.visible = show_progress
	_bar_label.visible = show_progress
	if show_progress:
		var need := PlayerProfile.get_copies_to_next(id)
		if locked:
			_bar.max_value = 1
			_bar.value = 0
			_bar_label.text = "—"
		elif need < 0:
			_bar.max_value = 1
			_bar.value = 1
			_bar_fill.bg_color = GOLD.darkened(0.2)
			_bar_label.text = "MAX"
		else:
			_bar.max_value = maxi(1, need)
			_bar.value = mini(copies, need)
			_bar_fill.bg_color = BAR_READY if copies >= need else BAR_NORMAL
			_bar_label.text = "%d / %d" % [copies, need]
	_apply_state()
	_layout()

# Kolekcia: stav voci draftu (v balicku / odmietnuta draft bohom).
func set_state(is_in_deck: bool, is_forbidden: bool) -> void:
	in_deck = is_in_deck
	forbidden = is_forbidden
	_apply_state()

func is_blocked() -> bool:
	return locked or forbidden

func _apply_state() -> void:
	modulate = DIM if is_blocked() else Color.WHITE
	if _dragging:
		modulate.a = 0.0   # karta je "na prste" — miesto v mriezke ostane prazdne
	var status := ""
	if locked:
		status = "LOCKED"
	elif forbidden:
		status = "FORBIDDEN"
	elif in_deck and slot_index < 0:
		status = "IN DECK"
	_status_label.text = status
	_status_label.visible = status != ""

# Glow + obrys len pocas drzania (feedback "nabijania" dragu).
func _refresh_glow() -> void:
	var holding := _pressed and _hold_elapsed >= HOLD_FEEDBACK_DELAY and _can_drag()
	_glow.visible = holding
	_outline.visible = holding
	if holding:
		return  # alfu riadi _process podla postupu drzania
	_set_glow_alpha(1.0)

func _set_glow_alpha(a: float) -> void:
	_glow.modulate.a = a
	# obrys je vidiet uz od zaciatku nabijania
	_outline.modulate.a = 0.55 + 0.45 * a

# --- Layout (vsetko relativne k velkosti) ---

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_layout()
		NOTIFICATION_DRAG_END:
			if _dragging:
				_dragging = false
				_apply_state()

func _layout() -> void:
	if _art_clip == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var card := Rect2(Vector2.ZERO, size)
	if show_progress:
		card.size.y = size.y * (1.0 - BAR_RATIO) - BAR_GAP
		var bar_rect := Rect2(0.0, card.end.y + BAR_GAP, size.x, size.y - card.end.y - BAR_GAP)
		_set_rect(_bar, bar_rect)
		_set_rect(_bar_label, bar_rect)
		_bar_label.add_theme_font_size_override("font_size", maxi(8, int(bar_rect.size.y * 0.75)))

	var art_rect := card
	_set_rect(_art_clip, art_rect)
	_set_rect(_art, Rect2(Vector2.ZERO, art_rect.size))
	_set_rect(_glow, card.grow(card.size.x * 0.02))
	_set_rect(_outline, card.grow(1.0))

	var w := card.size.x
	var badge := w * 0.3
	var badge_rect := Rect2(card.position + Vector2(w * 0.03, w * 0.03), Vector2(badge, badge))
	_set_rect(_cost_badge, badge_rect)
	_set_rect(_cost_label, badge_rect)
	_cost_label.add_theme_font_size_override("font_size", maxi(8, int(badge * 0.62)))

	# Clip = len plocha karty (progres bar pod nou logo nikdy neprekryje).
	_set_rect(_logo_clip, card)
	var logo_w := card.size.x * LOGO_SIZE
	var logo_h := logo_w
	if _logo.texture != null:
		var tex := _logo.texture.get_size()
		logo_h = logo_w * tex.y / tex.x
	_set_rect(_logo, Rect2(Vector2(card.size.x - logo_w * (1.0 - LOGO_OVERHANG),
		card.size.y - logo_h * (1.0 - LOGO_OVERHANG)), Vector2(logo_w, logo_h)))

	var font := maxi(8, int(w * 0.13))
	var line_h := font * 1.4
	_level_label.add_theme_font_size_override("font_size", font)
	_level_label.add_theme_constant_override("outline_size", maxi(4, int(font * LEVEL_OUTLINE_RATIO)))
	_set_rect(_level_label, Rect2(art_rect.position.x, art_rect.end.y - line_h - w * 0.03, art_rect.size.x - w * 0.06, line_h))
	_status_label.add_theme_font_size_override("font_size", maxi(7, int(w * 0.1)))
	_set_rect(_status_label, Rect2(art_rect.position.x, art_rect.position.y + art_rect.size.y * 0.45, art_rect.size.x, font * 1.3))

func _set_rect(c: Control, rect: Rect2) -> void:
	c.position = rect.position
	c.size = rect.size

# Obraz boha: card_art (obal karty), inak prvy frame idle animacie
# (obaja sucasni bohovia maju preklep "iddle_left").
func _hero_texture(hero: HeroData) -> Texture2D:
	if hero.card_art != null:
		return hero.card_art
	var frames := hero.sprite_frames
	if frames == null:
		return null
	for anim in [&"iddle_left", &"idle_left"]:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			return frames.get_frame_texture(anim, 0)
	return null

# --- Vstup ---
# Len mouse eventy — emulate_touch_from_mouse + default mouse-from-touch
# pokryju desktop aj dotyk. ScreenTouch NEchytat, inak by tap padol 2x.

func _can_drag() -> bool:
	return draggable and not is_blocked() and item_id != &""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# pohyb prstom = scroll kolekcie, nie tap ani drzanie
		if _pressed and event.position.distance_to(_press_pos) > TAP_MAX_DISTANCE:
			_end_press()
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_pressed = true
		_press_pos = event.position
		_hold_elapsed = 0.0
		set_process(true)
		return
	if not _pressed:
		return
	var is_tap: bool = event.position.distance_to(_press_pos) <= TAP_MAX_DISTANCE
	_end_press()
	if is_tap:
		tapped.emit(self)   # aj locked / forbidden — detail sa da pozriet vzdy

func _end_press() -> void:
	_pressed = false
	_hold_elapsed = 0.0
	set_process(false)
	_refresh_glow()

func _process(delta: float) -> void:
	if not _pressed:
		set_process(false)
		return
	var before := _hold_elapsed
	_hold_elapsed += delta
	if not _can_drag():
		return
	if before < HOLD_FEEDBACK_DELAY and _hold_elapsed >= HOLD_FEEDBACK_DELAY:
		_refresh_glow()
	if _hold_elapsed >= HOLD_FEEDBACK_DELAY:
		# glow sa "nabija" az do zaciatku dragu
		var t := clampf((_hold_elapsed - HOLD_FEEDBACK_DELAY) / maxf(0.01, hold_to_drag_time - HOLD_FEEDBACK_DELAY), 0.0, 1.0)
		_set_glow_alpha(t)
	if _hold_elapsed >= hold_to_drag_time:
		_begin_drag()

func _begin_drag() -> void:
	_pressed = false
	_hold_elapsed = 0.0
	set_process(false)
	_refresh_glow()
	_dragging = true
	_apply_state()

	# Preview = karta v plnej velkosti (art + cost badge), vycentrovana na prste.
	var preview := Control.new()
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var card_size := _art_clip.size
	var holder := Control.new()
	holder.position = -card_size * 0.5
	holder.size = card_size
	preview.add_child(holder)
	var pic := TextureRect.new()
	pic.texture = _art.texture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size = card_size
	holder.add_child(pic)
	if _cost_badge.visible:
		# badge aj label su v suradniciach karty (art_clip zacina v 0,0)
		holder.add_child(_cost_badge.duplicate())
		holder.add_child(_cost_label.duplicate())

	hold_drag_started.emit(self)
	force_drag({"id": item_id, "kind": kind, "from_slot": slot_index}, preview)

# Zabudovany drag (pohyb mysou) je vypnuty — drag zacina len drzanim.
func _get_drag_data(_pos: Vector2) -> Variant:
	return null

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if slot_index < 0:
		return false
	if not (data is Dictionary) or not data.has("kind") or not data.has("id"):
		return false
	if data["id"] == item_id:
		return false
	if slot_index == 0:
		return data["kind"] == DeckTile.KIND_HERO
	return data["kind"] == DeckTile.KIND_CARD

func _drop_data(_pos: Vector2, data: Variant) -> void:
	dropped.emit(data, self)
