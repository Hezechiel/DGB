extends Control
class_name RewardsOverlay

# RewardsOverlay — Rewards tab ("Divine Rewards"): fronta zarobenych relikviarov
# (FREE casovac / DAILY PLAY / VICTORY), vybrany sa ukazuje na Stage a otvara sa
# okamzite cez PlayerProfile.open_reliquary() -> PackReveal.
# MainMenu tab page (activate()/deactivate()). Zbierku meni LEN PlayerProfile;
# tato stranka nikdy neposiela cenu ani vysledok hodu.
# Prazdna fronta -> spodny rad ukaze balicky zo Shopu (tap -> shop_requested).

# Tap na kartu v reveal-e -> MainMenu otvori CardDetail
signal card_detail_requested(id: StringName, kind: StringName)
# Tap na "reklamu" balicka -> MainMenu prepne na Shop (na balicky)
signal shop_requested

# Rovnake hodnoty ako ShopOverlay
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Unique"]
const RARITY_COLORS := [
	Color(0.75, 0.75, 0.78),
	Color(0.35, 0.6, 1.0),
	Color(0.7, 0.4, 1.0),
	Color(1.0, 0.6, 0.15),
	Color(1.0, 0.82, 0.3),
]
const CURRENCY_ICONS := {
	&"gold": preload("res://assets/menu/coin.png"),
	&"crystals": preload("res://assets/menu/crystal.png"),
}
const FRAME_TEX := preload("res://assets/menu/frame_ninepatchrect.png")
const GOLD := Color(1.0, 0.8, 0.35)
const SUBTLE := Color(0.85, 0.85, 0.9)
const PRICE_COLOR := Color(1.0, 0.96, 0.85)
const ART_PLACEHOLDER := Color(1, 0, 1)   # magenta = chyba art
const TAP_MAX_DISTANCE := 10.0     # rovnako ako DeckCardTile / Pantheon

const QUEUE_TILE_WIDTH := 110.0
const QUEUE_CHEST := Vector2(72, 72)
const AD_CHEST := Vector2(64, 64)
const SELECTED_BORDER := Color(1.0, 0.8, 0.35)
const EMPTY_CHEST_TINT := Color(1, 1, 1, 0.35)
const DISABLED_TINT := Color(0.5, 0.5, 0.5)
const HELD_TINT := Color(0.8, 0.8, 0.8)
const PIP_DONE := Color(1.0, 0.8, 0.35)
const PIP_EMPTY := Color(0.06, 0.09, 0.16)

@onready var layout: VBoxContainer = %Layout
@onready var chest_art: TextureRect = %ChestArt
@onready var chest_name: Label = %ChestName
@onready var chest_source: Label = %ChestSource
@onready var open_button: TextureButton = %OpenButton
@onready var open_label: Label = %OpenLabel
@onready var play_text: Label = %PlayText
@onready var play_count: Label = %PlayCount
@onready var play_pips: Control = %PlayPips
@onready var play_thumb: TextureRect = %PlayThumb
@onready var free_text: Label = %FreeText
@onready var free_timer: Label = %FreeTimer
@onready var free_thumb: TextureRect = %FreeThumb
@onready var queue_scroll: ScrollContainer = %QueueScroll
@onready var queue_list: HBoxContainer = %QueueList
@onready var ad_scroll: ScrollContainer = %AdScroll
@onready var ad_list: HBoxContainer = %AdList
@onready var reveal: PackReveal = %Reveal

var _selected: int = 0
var _queue_tiles: Array[PanelContainer] = []
var _press: Dictionary = {}   # tile -> pozicia stlacenia
var _tick: Timer

func _ready() -> void:
	visible = false
	PlayerProfile.rewards_changed.connect(_on_rewards_changed)
	open_button.pressed.connect(_on_open_pressed)
	open_button.button_down.connect(_refresh_open_tint)
	open_button.button_up.connect(_refresh_open_tint)
	reveal.closed.connect(_on_reveal_closed)
	reveal.card_detail_requested.connect(func(id: StringName, kind: StringName): card_detail_requested.emit(id, kind))
	play_pips.draw.connect(_draw_pips)

	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.one_shot = false
	_tick.timeout.connect(_on_tick)
	add_child(_tick)

	# nahlady v info paneli sa nemenia (pack id je v RewardsConfig)
	play_thumb.texture = _pack_chest(PlayerProfile.REWARDS.play_pack_id)
	free_thumb.texture = _pack_chest(PlayerProfile.REWARDS.free_pack_id)

func activate() -> void:
	PlayerProfile.update_reward_timers()
	_selected = 0
	_show_layout()
	_refresh()
	_tick.start()
	visible = true

func deactivate() -> void:
	_tick.stop()
	reveal.hide_reveal()
	_show_layout()
	visible = false

func _show_layout() -> void:
	layout.visible = true

# Mimo tabu sa neprestavuje — activate() aj tak obnovi vsetko.
func _on_rewards_changed() -> void:
	if visible:
		_refresh()

# Kazdu sekundu: dobehne casovac (pridanie free relikviara -> rewards_changed ->
# _refresh) a prepise LEN odpocet.
func _on_tick() -> void:
	PlayerProfile.update_reward_timers()
	_update_free_timer()

func _refresh() -> void:
	var queue := PlayerProfile.get_reliquary_queue()
	_selected = clampi(_selected, 0, maxi(queue.size() - 1, 0))
	_rebuild_bottom(queue)
	_update_stage(queue)
	_update_play()
	_update_free_timer()

# --- Stage ---

func _update_stage(queue: Array[StringName]) -> void:
	var has_any := not queue.is_empty()
	if has_any:
		var pack_id := queue[_selected]
		var pack := _get_pack_or_null(pack_id)
		chest_art.texture = _pack_chest(pack_id)
		chest_art.modulate = Color.WHITE
		chest_name.text = pack.display_name.to_upper() if pack != null else String(pack_id)
		chest_source.text = _source_text(pack_id)
	else:
		# prazdna fronta — tlmena free truhlica ako "co pride"
		chest_art.texture = _pack_chest(PlayerProfile.REWARDS.free_pack_id)
		chest_art.modulate = EMPTY_CHEST_TINT
		chest_name.text = ""
		chest_source.text = ""
	open_button.disabled = not has_any
	open_label.text = "OPEN RELIQUARY" if has_any else "NO RELIQUARIES"
	_refresh_open_tint()

func _source_text(pack_id: StringName) -> String:
	var cfg := PlayerProfile.REWARDS
	if pack_id == cfg.free_pack_id:
		return "Free"
	if pack_id == cfg.play_pack_id:
		return "Daily play"
	if pack_id == cfg.victory_pack_id:
		return "Victory"
	return "Reward"

# TextureButton nema disabled texturu -> stav sa kresli tintom.
func _refresh_open_tint() -> void:
	if open_button.disabled:
		open_button.self_modulate = DISABLED_TINT
		open_label.modulate = DISABLED_TINT
	elif open_button.is_pressed():
		open_button.self_modulate = HELD_TINT
		open_label.modulate = Color.WHITE
	else:
		open_button.self_modulate = Color.WHITE
		open_label.modulate = Color.WHITE

func _on_open_pressed() -> void:
	_refresh_open_tint()
	if PlayerProfile.get_reliquary_queue().is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res := PlayerProfile.open_reliquary(_selected, rng)
	if res.is_empty():
		return
	var pack := _get_pack_or_null(res["pack_id"])
	var cards: Array[StringName] = res["cards"]
	var is_new: Array[bool] = res["is_new"]
	layout.visible = false
	reveal.show_result(pack.display_name if pack != null else String(res["pack_id"]), cards, is_new)

func _on_reveal_closed() -> void:
	_show_layout()
	_selected = 0
	_refresh()

# --- Info panel ---

func _update_play() -> void:
	var progress := PlayerProfile.get_play_progress()
	var goal: int = progress["goal"]
	if progress["claimed"]:
		play_text.text = "Earned today — come back tomorrow"
	else:
		play_text.text = "Play %d matches today to earn a Play Reliquary!" % goal
	play_count.text = "%d / %d" % [progress["count"], goal]
	play_pips.queue_redraw()

func _draw_pips() -> void:
	var progress := PlayerProfile.get_play_progress()
	var goal: int = progress["goal"]
	var done: int = progress["count"]
	var radius := play_pips.size.y / 2.0 - 1.0
	if goal <= 0 or radius <= 0.0:
		return
	var step := radius * 2.0 + 5.0
	for i in goal:
		var center := Vector2(radius + 1.0 + i * step, play_pips.size.y / 2.0)
		if i < done:
			play_pips.draw_circle(center, radius, PIP_DONE)
		else:
			play_pips.draw_circle(center, radius, PIP_EMPTY)
			play_pips.draw_arc(center, radius, 0.0, TAU, 24, PIP_DONE, 1.5, true)

@warning_ignore("integer_division")
func _update_free_timer() -> void:
	var left := PlayerProfile.get_free_reliquary_seconds_left()
	if left < 0:
		free_text.visible = false
		free_timer.text = "Ready to open (%d/%d)" % [
			PlayerProfile.get_free_reliquary_stock(), PlayerProfile.REWARDS.free_max_stock]
	else:
		free_text.visible = true
		free_timer.text = "%02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]

# --- Spodny rad: fronta alebo reklama na Shop ---

func _rebuild_bottom(queue: Array[StringName]) -> void:
	_free_children(queue_list)
	_free_children(ad_list)
	_queue_tiles.clear()
	_press.clear()
	var has_any := not queue.is_empty()
	queue_scroll.visible = has_any
	ad_scroll.visible = not has_any
	if has_any:
		for i in queue.size():
			var tile := _build_queue_tile(queue[i], i)
			queue_list.add_child(tile)
			_queue_tiles.append(tile)
		_apply_selection()
	else:
		for pack in _shop_packs():
			ad_list.add_child(_build_ad_tile(pack))

# Rovnaky vyber a poradie ako ShopOverlay._sorted_packs().
func _shop_packs() -> Array[PackData]:
	var packs: Array[PackData] = []
	for pack_id in CardDB.list_pack_ids():
		var pack := CardDB.get_pack(pack_id)
		if pack != null and pack.shop_visible:
			packs.append(pack)
	packs.sort_custom(func(a: PackData, b: PackData) -> bool:
		if a.shop_order != b.shop_order:
			return a.shop_order < b.shop_order
		return a.id < b.id)
	return packs

func _build_queue_tile(pack_id: StringName, index: int) -> PanelContainer:
	var pack := _get_pack_or_null(pack_id)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	var art := _art_or_placeholder(pack.chest_texture_path if pack != null else "", QUEUE_CHEST)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(art)
	var name_label := _make_label(pack.display_name if pack != null else String(pack_id), 13, GOLD, 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var source_label := _make_label(_source_text(pack_id), 11, SUBTLE, 0)
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(source_label)

	var tile := _make_framed_tile(box, 0.35, 6)
	tile.custom_minimum_size = Vector2(QUEUE_TILE_WIDTH, 0)
	_make_tappable(tile, _on_queue_tile_tapped.bind(index))
	return tile

# Vyber len prefarbi ramy — ziadna prestavba.
func _apply_selection() -> void:
	for i in _queue_tiles.size():
		var tile := _queue_tiles[i]
		if not is_instance_valid(tile):
			continue
		if i == _selected:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.border_color = SELECTED_BORDER
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(6)
			tile.add_theme_stylebox_override("panel", sb)
		else:
			tile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

func _on_queue_tile_tapped(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	_apply_selection()
	_update_stage(PlayerProfile.get_reliquary_queue())

# Rovnake rozlozenie ako balicek v Shope, ale cena je len text (ziadny nakup tu).
func _build_ad_tile(pack: PackData) -> PanelContainer:
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	var art := _art_or_placeholder(pack.chest_texture_path, AD_CHEST)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(art)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)
	vbox.add_child(_make_label(pack.display_name, 16, GOLD, 4))
	vbox.add_child(_make_label("%d CARDS" % pack.card_count, 13, SUBTLE, 0))
	vbox.add_child(_make_guarantee_label(pack.guaranteed_min_rarity))

	var price_row := HBoxContainer.new()
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_theme_constant_override("separation", 4)
	var icon_tex: Texture2D = CURRENCY_ICONS.get(pack.currency)
	if pack.price > 0 and icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price_row.add_child(icon)
	var price_text := "FREE" if pack.price <= 0 else CurrencyCounter.format_amount(pack.price)
	price_row.add_child(_make_label(price_text, 15, PRICE_COLOR, 3))
	vbox.add_child(price_row)

	var tile := _make_framed_tile(hbox, 0.35, 8)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_make_tappable(tile, func(): shop_requested.emit())
	return tile

# --- Tap detekcia (rovnake pravidlo ako PackReveal / Pantheon hlavicka) ---
# PASS: swipe po dlazdici stale scrolluje rad; len mouse eventy, nie ScreenTouch.

func _make_tappable(tile: Control, on_tap: Callable) -> void:
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.gui_input.connect(_on_tile_input.bind(tile, on_tap))

func _on_tile_input(event: InputEvent, tile: Control, on_tap: Callable) -> void:
	if event is InputEventMouseMotion:
		if _press.has(tile) and event.position.distance_to(_press[tile]) > TAP_MAX_DISTANCE:
			_press.erase(tile)
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press[tile] = event.position
		return
	if not _press.has(tile):
		return
	var is_tap: bool = event.position.distance_to(_press[tile]) <= TAP_MAX_DISTANCE
	_press.erase(tile)
	if is_tap:
		on_tap.call()

# --- Data helpers ---

# CardDB.get_pack() na nezname id hlasi push_error — zo savu ich PlayerProfile uz vyhodil.
func _get_pack_or_null(pack_id: StringName) -> PackData:
	if not CardDB.list_pack_ids().has(pack_id):
		return null
	return CardDB.get_pack(pack_id)

func _pack_chest(pack_id: StringName) -> Texture2D:
	var pack := _get_pack_or_null(pack_id)
	return _texture_or_null(pack.chest_texture_path) if pack != null else null

# --- Art + styling helpers (rovnake ako ShopOverlay) ---

func _texture_or_null(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

# Art slot s pevnou min. velkostou: PNG alebo magenta placeholder s nazvom suboru.
func _art_or_placeholder(path: String, min_size: Vector2) -> Control:
	var tex := _texture_or_null(path)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = min_size
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect
	var box := ColorRect.new()
	box.color = ART_PLACEHOLDER
	box.custom_minimum_size = min_size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_label(path.get_file(), 10, Color.WHITE, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box

func _make_guarantee_label(min_rarity: int) -> Control:
	var rarity := clampi(min_rarity, 0, RARITY_NAMES.size() - 1)
	var word := "[color=#%s]%s[/color]" % [RARITY_COLORS[rarity].to_html(false), RARITY_NAMES[rarity]]
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_color_override("default_color", SUBTLE)
	if min_rarity <= 0:
		label.text = "%s or better" % word
	else:
		label.text = "Guaranteed %s or better" % word
	return label

# Ramovany tile v kode: StyleBoxEmpty panel + Frame prvy potomok + Margin (ako Pantheon).
func _make_framed_tile(content: Control, patch_scale: float, margin: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var frame := ScaledNinePatch.new()
	frame.name = "Frame"
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.texture = FRAME_TEX
	frame.patch_margin_left = 52
	frame.patch_margin_top = 46
	frame.patch_margin_right = 52
	frame.patch_margin_bottom = 46
	frame.patch_scale = patch_scale
	frame.fill_color = Color(0.05, 0.07, 0.12, 0.86)
	frame.fill_inset = 3.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)

	var margin_box := MarginContainer.new()
	margin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin_box.add_theme_constant_override("margin_" + side, margin)
	margin_box.add_child(content)
	panel.add_child(margin_box)
	return panel

func _make_label(text: String, font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0))
		label.add_theme_constant_override("outline_size", outline)
	return label

func _free_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
