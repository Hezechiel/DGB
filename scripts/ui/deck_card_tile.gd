extends Control
class_name DeckCardTile

# DeckCardTile — karta v Deck obrazovke (sloty balicka aj Card Collection),
# v Pantheon encyklopedii a v ponuke Shopu. Art karty ma vlastny namalovany
# ram — zobrazi sa CELY (keep aspect, bez orezu); dlazdica = len karta.
# Vsetky overlaye sa kotvia k realne vykreslenemu artu (_card_rect), takze nic
# netrci cez namalovany ram:
#   cost badge vlavo hore, logo panteonu vpravo hore (rovnako velke ako badge),
#   dole cez kartu NameBanner (meno) a pod nim InfoStrip: "Lv N" vlavo,
#   zelena sipka (da sa vylepsit), progres kopii "5 / 4" (len show_progress;
#   bez neho len prazdny bar + "Lv N"). Status (IN DECK / LOCKED / FORBIDDEN)
#   v strede. Vsetky rozmery sa pocitaju z aktualnej velkosti — kartu len
#   natiahne/zmensi rodicovsky kontajner.
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
# Badge (cost vlavo, logo vpravo) a jeho odsadenie od okraja — podiel sirky karty.
const BADGE_SIZE := 0.3
const BADGE_INSET := 0.03
# Spodny overlay (podiel sirky karty). Ladit podla artu.
const STRIP_H := 0.13        # InfoStrip: Lv + sipka + progres
const BANNER_H := 0.17       # NameBanner nad stripom
const SIDE_INSET := 0.04
const BOTTOM_INSET := 0.03
const LV_SEGMENT := 0.42     # podiel stripu pre "Lv N" + sipku; zvysok je bar
# Hrubka obrysu "Lv N" ako podiel velkosti fontu.
const LEVEL_OUTLINE_RATIO := 0.45

const GOLD := Color(1.0, 0.82, 0.35)
const DIM := Color(0.42, 0.42, 0.42)
const BAR_READY := Color(0.28, 0.72, 0.22)
const BAR_NORMAL := Color(0.2, 0.5, 0.9)
const OVERLAY_BG := Color(0.03, 0.04, 0.08, 0.78)
const BANNER_BORDER := Color(0.85, 0.68, 0.3, 0.9)
const NAME_FONT := preload("res://assets/fonts/Oswald/static/Oswald-Bold.ttf")

# Zelena sipka "da sa vylepsit" — kreslena v kode, ziadny asset.
class UpgradeArrow extends Control:
	const COLOR := Color(0.45, 1.0, 0.35)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var s := size
		var pts := PackedVector2Array([
			Vector2(0.5, 0.0) * s, Vector2(1.0, 0.55) * s, Vector2(0.68, 0.55) * s,
			Vector2(0.68, 1.0) * s, Vector2(0.32, 1.0) * s, Vector2(0.32, 0.55) * s,
			Vector2(0.0, 0.55) * s])
		draw_colored_polygon(pts, COLOR)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color.BLACK, 1.0, true)

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
var _logo: TextureRect
var _name_label: Label
var _name_sb: StyleBoxFlat
var _strip_bg: Panel
var _level_label: Label
var _arrow: UpgradeArrow
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

	# Poradie add_child = poradie kreslenia: glow (pod kartou) -> art -> logo ->
	# cost badge -> banner -> strip -> sipka -> status -> obrys.
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

	# Logo vpravo hore — stvorec velkosti badge, logo v nom drzi pomer stran.
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

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

	# NameBanner — tmavy pas s tenkym zlatym okrajom hore, meno VELKYMI.
	_name_label = _make_label(3)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_override("font", NAME_FONT)
	_name_label.add_theme_color_override("font_color", GOLD)
	_name_sb = StyleBoxFlat.new()
	_name_sb.bg_color = OVERLAY_BG
	_name_sb.border_color = BANNER_BORDER
	_name_sb.border_width_top = 1
	_name_label.add_theme_stylebox_override("normal", _name_sb)

	# InfoStrip — podklad cez celu sirku, vlavo "Lv N" + sipka, vpravo bar.
	_strip_bg = Panel.new()
	_strip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_sb := StyleBoxFlat.new()
	strip_sb.bg_color = OVERLAY_BG
	_strip_bg.add_theme_stylebox_override("panel", strip_sb)
	add_child(_strip_bg)

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
	add_child(_bar)

	_level_label = _make_label(4)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bar_label = _make_label(3)
	_bar_label.visible = false

	_arrow = UpgradeArrow.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	add_child(_arrow)

	_status_label = _make_label(4)
	var status_sb := StyleBoxFlat.new()
	status_sb.bg_color = Color(0, 0, 0, 0.6)
	status_sb.set_corner_radius_all(3)
	_status_label.add_theme_stylebox_override("normal", status_sb)

	# Obrys NAD vsetkym — glow pod kartou v kolekcii orezava scroll, obrys nie.
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
# Progres je uz v karte -> _with_progress sa ignoruje (signatura ostava).
static func width_for_height(height: float, card_aspect: float, _with_progress: bool) -> float:
	return maxf(1.0, height * card_aspect)

# Vyska dlazdice pre danu sirku — inverzia width_for_height (WrapCardGrid
# v encyklopedii ma sirku danu stlpcami).
static func height_for_width(width: float, card_aspect: float, _with_progress: bool) -> float:
	return maxf(1.0, width / card_aspect)

func setup(id: StringName, tile_kind: StringName, slot: int) -> void:
	item_id = id
	kind = tile_kind
	slot_index = slot
	var tex: Texture2D = null
	var faction: StringName = &""
	var cost := -1
	var level := 0
	var copies := 0
	var display_name := String(id)
	tooltip_text = String(id)

	if kind == DeckTile.KIND_HERO:
		locked = not PlayerProfile.owns_hero(id)
		var hero: HeroData = CardDB.get_hero(id) if CardDB.has_hero(id) else null
		if hero != null:
			tex = _hero_texture(hero)
			faction = hero.faction
			display_name = hero.display_name
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
			display_name = card.display_name
			tooltip_text = card.display_name
		level = PlayerProfile.get_card_level(id)
		copies = PlayerProfile.get_card_copies(id)

	_art.texture = tex
	_cost_badge.visible = cost >= 0
	_cost_label.visible = cost >= 0
	_cost_label.text = str(cost)
	_logo.texture = logo_for(faction)
	_logo.visible = _logo.texture != null
	_name_label.text = display_name.to_upper()
	_level_label.text = "Lv %d" % level
	_level_label.visible = not locked

	# Bez show_progress: prazdny bar (bez vyplne a poctu) + len "Lv N".
	_bar.max_value = 1
	_bar.value = 0
	_bar_fill.bg_color = BAR_NORMAL
	_bar_label.visible = show_progress
	_arrow.visible = false
	if show_progress:
		var need := PlayerProfile.get_copies_to_next(id)
		if locked:
			_bar_label.text = "—"
		elif need < 0:
			_bar.value = 1
			_bar_fill.bg_color = GOLD.darkened(0.2)
			_bar_label.text = "MAX"
		else:
			_bar.max_value = maxi(1, need)
			_bar.value = mini(copies, need)
			_bar_fill.bg_color = BAR_READY if copies >= need else BAR_NORMAL
			_bar_label.text = "%d / %d" % [copies, need]
			_arrow.visible = copies >= need
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

# Plocha, ktoru art realne zabera (KEEP_ASPECT_CENTERED fit); bez artu cela dlazdica.
func _card_rect() -> Rect2:
	var rect := Rect2(Vector2.ZERO, size)
	if _art.texture == null:
		return rect
	var tex := _art.texture.get_size()
	if tex.x <= 0.0 or tex.y <= 0.0:
		return rect
	var s := minf(size.x / tex.x, size.y / tex.y)
	var drawn := tex * s
	return Rect2((size - drawn) * 0.5, drawn)

func _layout() -> void:
	if _art_clip == null or size.x <= 0.0 or size.y <= 0.0:
		return
	# art_clip/art ostavaju cez celu dlazdicu (drag preview s tym pocita)
	_set_rect(_art_clip, Rect2(Vector2.ZERO, size))
	_set_rect(_art, Rect2(Vector2.ZERO, size))

	var card := _card_rect()
	var w := card.size.x
	_set_rect(_glow, card.grow(w * 0.02))
	_set_rect(_outline, card.grow(1.0))

	# Badge vlavo hore (cost) a vpravo hore (logo) — rovnaka velkost a odsadenie.
	var badge := w * BADGE_SIZE
	var inset := w * BADGE_INSET
	var badge_rect := Rect2(card.position + Vector2(inset, inset), Vector2(badge, badge))
	_set_rect(_cost_badge, badge_rect)
	_set_rect(_cost_label, badge_rect)
	_cost_label.add_theme_font_size_override("font_size", maxi(8, int(badge * 0.62)))
	_set_rect(_logo, Rect2(Vector2(card.end.x - inset - badge, card.position.y + inset), Vector2(badge, badge)))

	# Spodny overlay: InfoStrip uplne dole, NameBanner nad nim.
	var side := w * SIDE_INSET
	var strip_h := w * STRIP_H
	var strip := Rect2(card.position.x + side, card.end.y - w * BOTTOM_INSET - strip_h, w - 2.0 * side, strip_h)
	_set_rect(_strip_bg, strip)

	var banner_h := w * BANNER_H
	var banner := Rect2(strip.position.x, strip.position.y - banner_h, strip.size.x, banner_h)
	# font ~ w*0.12, ale tak, aby vyska riadku nevytlacila label z bannera
	var name_font := maxi(8, int(minf(w * 0.12, banner_h / 1.5)))
	_name_label.add_theme_font_size_override("font_size", name_font)
	_name_label.add_theme_constant_override("outline_size", maxi(2, int(name_font * 0.3)))
	_name_sb.content_margin_left = side * 0.5
	_name_sb.content_margin_right = side * 0.5
	_name_sb.content_margin_top = 0
	_name_sb.content_margin_bottom = 0
	_set_rect(_name_label, banner)

	var strip_font := maxi(7, int(strip_h / 1.45))
	var pad := strip_h * 0.2
	var segment := strip.size.x * LV_SEGMENT
	_level_label.add_theme_font_size_override("font_size", strip_font)
	_level_label.add_theme_constant_override("outline_size", maxi(2, int(strip_font * LEVEL_OUTLINE_RATIO)))
	_set_rect(_level_label, Rect2(strip.position.x + pad, strip.position.y, segment - pad, strip_h))

	# Sipka hned za textom "Lv N"
	var text_w := _level_label.get_theme_font("font").get_string_size(
		_level_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, strip_font).x
	var arrow_s := strip_h * 0.8
	_set_rect(_arrow, Rect2(strip.position.x + pad + text_w + pad * 0.5,
		strip.position.y + (strip_h - arrow_s) * 0.5, arrow_s, arrow_s))

	var bar_x := strip.position.x + segment
	var bar_rect := Rect2(bar_x, strip.position.y + strip_h * 0.18, strip.end.x - pad - bar_x, strip_h * 0.64)
	_set_rect(_bar, bar_rect)
	_set_rect(_bar_label, Rect2(bar_rect.position.x, strip.position.y, bar_rect.size.x, strip_h))
	_bar_label.add_theme_font_size_override("font_size", strip_font)

	var status_font := maxi(7, int(w * 0.1))
	_status_label.add_theme_font_size_override("font_size", status_font)
	_set_rect(_status_label, Rect2(card.position.x, card.position.y + card.size.y * 0.45, w, status_font * 1.3))

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
