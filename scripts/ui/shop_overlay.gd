extends Control
class_name ShopOverlay

# ShopOverlay — Shop tab: denna odmena, dalsia odmena, ponuka kariet, balicky
# -> otvorenie balicka -> reveal. Ramovane panely rovnako ako Pantheon/Deck.
# MainMenu tab page (activate()/deactivate()).
# Losovanie robi cisty PackRoller; zbierku meni LEN PlayerProfile (mutacne API).
# Balicky stoja menu (PlayerProfile penazenka); denna odmena je zatial TESTER
# faucet (bez limitu); ponuka kariet sa kupuje cez PlayerProfile (refresh zatial
# zadarmo); casovace su stuby.
# Art: chybajuci subor -> farebny placeholder rovnakej velkosti (nic sa nehybe).

# Tap na kartu (ponuka aj reveal) -> MainMenu otvori CardDetail
signal card_detail_requested(id: StringName, kind: StringName)

const RARITY_NAMES :=["Common", "Rare", "Epic", "Legendary", "Unique"]
# Farba slova rarity, index = rarity (rovnaka paleta ako card_detail.gd).
const RARITY_COLORS := [
	Color(0.75, 0.75, 0.78),
	Color(0.35, 0.6, 1.0),
	Color(0.7, 0.4, 1.0),
	Color(1.0, 0.6, 0.15),
	Color(1.0, 0.82, 0.3),
]

const SHOP_ART := "res://assets/menu/shop/"
const POUCH_PATH := SHOP_ART + "pouch.png"
const BUTTON_PATHS := {
	&"free": SHOP_ART + "btn_free.png",
	&"gold": SHOP_ART + "btn_gold.png",
	&"crystals": SHOP_ART + "btn_diamond.png",
}
const PLACEHOLDER_COLORS := {
	&"free": Color(0, 1, 1),
	&"gold": Color(1, 0.5, 0),
	&"crystals": Color(0.2, 0.2, 1),
}
const CURRENCY_ICONS := {
	&"gold": preload("res://assets/menu/coin.png"),
	&"crystals": preload("res://assets/menu/crystal.png"),
}
const PRICE_ICON_WIDTH := 20
const PRICE_COLOR := Color(1.0, 0.96, 0.85)
const UNAFFORDABLE := Color(1, 0.4, 0.35)    # cena, na ktoru hrac nema
const MESSAGE_HOLD := 1.5
const MESSAGE_FADE := 0.3
const ART_PLACEHOLDER := Color(1, 0, 1)   # magenta = chyba art
# 9-slice okraje art tlacidla v px zdrojovej textury (840x245); rohy sa zmensuju cez ScaledNinePatch
const BUTTON_PATCH_X := 70
const BUTTON_PATCH_Y := 60
const BUTTON_MARGIN_X := 8.0              # obsahove okraje — rovnake pre texturu aj placeholder
const BUTTON_MARGIN_Y := 2.0

const FRAME_TEX := preload("res://assets/menu/frame_ninepatchrect.png")
const BOLD_FONT := preload("res://assets/fonts/Oswald/static/Oswald-Bold.ttf")
const GOLD := Color(1.0, 0.8, 0.35)
const SUBTLE := Color(0.85, 0.85, 0.9)
const CARD_ASPECT := 0.82          # rovnako ako pantheon_overlay.gd
const SOLD_TINT := Color(0.45, 0.45, 0.45)   # kupena ponuka
const CHEST_SLOT := Vector2(96, 96)
const POUCH_SLOT := Vector2(72, 72)
const NEXT_REWARD_HOURS := [2, 6, 12, 24]
const TAP_MAX_DISTANCE := 10.0     # rovnako ako DeckCardTile / Pantheon

@onready var shop_scroll: ScrollContainer = %ShopScroll   # cely obsah shopu (Layout) scrolluje tahom
@onready var pouch_holder: Control = %PouchHolder
@onready var claim_button: Button = %ClaimButton
@onready var daily_kind: Label = %DailyKind
@onready var gold_range: Label = %GoldRange
@onready var crystal_range: Label = %CrystalRange
@onready var next_slots: HBoxContainer = %NextSlots
@onready var refresh_button: Button = %RefreshButton
@onready var offers_row: HBoxContainer = %OffersRow
@onready var packs_row: HBoxContainer = %PacksRow
@onready var reveal: PackReveal = %RevealPanel   # instancia pack_reveal.tscn

var _offer_tiles: Array[DeckCardTile] = []
var _buy_buttons: Dictionary = {}   # Button -> PackData
var _offer_buttons: Dictionary = {} # Button -> {currency, price} (len nekupene ponuky)
var _message_label: Label
var _message_tween: Tween
var _press_scroll_y: int = 0   # scroll pri stlaceni tlacidla

func _ready() -> void:
	visible = false
	reveal.closed.connect(_show_pack_view)
	reveal.card_detail_requested.connect(func(id: StringName, kind: StringName): card_detail_requested.emit(id, kind))
	PlayerProfile.profile_changed.connect(_on_profile_changed)
	# zmena zostatku -> len prefarbi ceny, ziadna prestavba
	PlayerProfile.wallet_changed.connect(func(_currency: StringName, _amount: int): _refresh_price_colors())
	# refresh / kupa -> prestavba LEN radu ponuky
	PlayerProfile.offers_changed.connect(_rebuild_offers)

	# TESTER faucet — bez limitu; TODO(economy): cooldown + next-reward track
	_style_shop_button(claim_button, &"free")
	claim_button.pressed.connect(_on_claim_pressed)
	_fill_holder(pouch_holder, _art_or_placeholder(POUCH_PATH, POUCH_SLOT))
	_fill_daily_texts()

	# TODO(economy): dalsia odmena — progres a odomykanie, zatial len "?" sloty
	for hours in NEXT_REWARD_HOURS:
		next_slots.add_child(_build_next_slot(hours))

	# TESTER: refresh zadarmo bez limitu; TODO(economy): cena + casovac
	_style_shop_button(refresh_button, &"free")
	refresh_button.text = "REFRESH"
	refresh_button.pressed.connect(_on_refresh_pressed)

func activate() -> void:
	_rebuild_offers()

	_free_children(packs_row)
	_buy_buttons.clear()
	for pack in _sorted_packs():
		packs_row.add_child(_build_pack_tile(pack))

	_show_pack_view()
	shop_scroll.scroll_vertical = 0   # shop sa otvara navrchu
	visible = true

func deactivate() -> void:
	_show_pack_view()
	visible = false

# Rewards "reklama" -> Shop tab rovno na balicky. Vola sa PO activate() (ten scrollne navrch).
func scroll_to_packs() -> void:
	await get_tree().process_frame   # ShopScroll musi mat prepocitany rozsah po activate()
	shop_scroll.ensure_control_visible(packs_row)

func _show_pack_view() -> void:
	shop_scroll.visible = true
	reveal.hide_reveal()

# --- Drag guard (tlacidla v ShopScroll) ---

# PASS: tah zacaty na tlacidle stale scrolluje ShopScroll
func _guard_shop_button(button: Button) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	if not button.button_down.is_connected(_on_shop_button_down):
		button.button_down.connect(_on_shop_button_down)

func _on_shop_button_down() -> void:
	_press_scroll_y = shop_scroll.scroll_vertical

# true = medzi down a pressed sa scrollovalo -> nie je to tap
func _scrolled_since_press() -> bool:
	return absi(shop_scroll.scroll_vertical - _press_scroll_y) > int(TAP_MAX_DISTANCE)

# --- Denna odmena ---

# Texty z PlayerProfile.DAILY_REWARD (len citanie).
func _fill_daily_texts() -> void:
	var reward := PlayerProfile.DAILY_REWARD
	daily_kind.text = "FREE GOLD & CRYSTALS"
	gold_range.text = _range_text(reward.gold_min, reward.gold_max)
	crystal_range.text = _range_text(reward.crystals_min, reward.crystals_max)

func _range_text(lo: int, hi: int) -> String:
	return "%s – %s" % [CurrencyCounter.format_amount(lo), CurrencyCounter.format_amount(hi)]

# Zostatky v top bare a farby cien sa obnovia samy cez wallet_changed.
func _on_claim_pressed() -> void:
	if _scrolled_since_press(): return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got := PlayerProfile.claim_daily_reward(rng)
	_show_shop_message("+%s gold   +%s crystals" % [
		CurrencyCounter.format_amount(got[PlayerProfile.CURRENCY_GOLD]),
		CurrencyCounter.format_amount(got[PlayerProfile.CURRENCY_CRYSTALS])])

# --- Ponuka kariet ---

# Prestavi LEN offers_row (+ _offer_tiles/_offer_buttons) — Layout/RevealPanel nechava.
func _rebuild_offers() -> void:
	_free_children(offers_row)
	_offer_tiles.clear()
	_offer_buttons.clear()
	var offers := PlayerProfile.get_card_offers()
	for i in offers.size():
		offers_row.add_child(_build_offer_tile(offers[i], i))

func _on_refresh_pressed() -> void:
	if _scrolled_since_press(): return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	PlayerProfile.refresh_card_offers(rng)

# Ceny/kopie pozna len PlayerProfile — shop iba zobrazuje a posiela index.
func _on_offer_buy_pressed(index: int) -> void:
	if _scrolled_since_press(): return
	var offers := PlayerProfile.get_card_offers()
	if index < 0 or index >= offers.size() or offers[index]["bought"]:
		return
	var id: StringName = offers[index]["id"]
	var p := PlayerProfile.get_offer_price(id)
	if p.is_empty():
		return
	if PlayerProfile.buy_card_offer(index):
		_show_shop_message("+%d %s" % [p["copies"], CardDB.get_card(id).display_name])
	else:
		_show_shop_message("Not enough %s" % p["currency"])

# --- Data ---

func _sorted_packs() -> Array[PackData]:
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

# --- Tiles ---

func _build_next_slot(hours: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16)
	sb.border_color = Color(0.25, 0.32, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -2)
	panel.add_child(box)
	box.add_child(_make_label("?", 20, GOLD, 4))
	box.add_child(_make_label("%dh" % hours, 11, SUBTLE, 0))
	for child in box.get_children():
		child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return panel

func _build_offer_tile(offer: Dictionary, index: int) -> Control:
	var id: StringName = offer["id"]
	var bought: bool = offer["bought"]
	var p := PlayerProfile.get_offer_price(id)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)

	# DeckCardTile vyplna cely svoj rect — pomer stran drzi AspectRatioContainer
	var aspect := AspectRatioContainer.new()
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.ratio = CARD_ASPECT   # dlazdica = len karta (progres je v nej)
	box.add_child(aspect)

	var tile := DeckCardTile.new()
	tile.show_progress = true
	tile.draggable = false
	tile.setup(id, DeckTile.KIND_CARD, -1)
	tile.tapped.connect(_on_offer_tile_tapped)
	aspect.add_child(tile)
	_offer_tiles.append(tile)

	var currency: StringName = p.get("currency", &"gold")
	var amount: int = p.get("price", 0)
	var copies_label := _make_label("×%d" % p.get("copies", 1), 13, GOLD, 3)
	copies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(copies_label)

	var price := Button.new()
	price.custom_minimum_size = Vector2(0, 30)
	_style_shop_button(price, currency)
	if bought:
		price.text = "SOLD"
		price.icon = null
		price.disabled = true
	else:
		price.text = CurrencyCounter.format_amount(amount)
		_set_price_icon(price, currency)
		price.pressed.connect(_on_offer_buy_pressed.bind(index))
		_offer_buttons[price] = {"currency": currency, "price": amount}
		_apply_price_color(price, PlayerProfile.can_afford(currency, amount))
	box.add_child(price)

	var panel := _make_framed_tile(box, 0.35, 6)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if bought:
		# cela dlazdica sivo; karta ostava tapnutelna (CardDetail)
		panel.modulate = SOLD_TINT
	return panel

func _on_offer_tile_tapped(tile: DeckCardTile) -> void:
	card_detail_requested.emit(tile.item_id, tile.kind)

# Level up v CardDetaile -> dlazdice ponuky ukazu novy level / kopie.
# Len re-setup, ZIADNA prestavba — grant_cards() v _open_pack() tiez emituje
# profile_changed a prestavba nesmie skryt reveal.
func _on_profile_changed() -> void:
	for tile in _offer_tiles:
		if is_instance_valid(tile):
			tile.setup(tile.item_id, tile.kind, -1)

func _build_pack_tile(pack: PackData) -> Control:
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)

	var art := _art_or_placeholder(pack.chest_texture_path, CHEST_SLOT)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(art)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var name_label := _make_label(pack.display_name, 16, GOLD, 4)
	vbox.add_child(name_label)
	vbox.add_child(_make_label("%d CARDS" % pack.card_count, 13, SUBTLE, 0))
	vbox.add_child(_make_guarantee_label(pack.guaranteed_min_rarity))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var buy := Button.new()
	buy.text = "FREE" if pack.price <= 0 else CurrencyCounter.format_amount(pack.price)
	buy.custom_minimum_size = Vector2(0, 34)
	_style_shop_button(buy, pack.currency)
	if pack.price > 0:
		_set_price_icon(buy, pack.currency)
	buy.pressed.connect(_open_pack.bind(pack.id))
	vbox.add_child(buy)
	_buy_buttons[buy] = pack
	_refresh_buy_button(buy, pack)

	var panel := _make_framed_tile(hbox, 0.35, 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel

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

# --- Reveal / otvorenie balicka ---

func _open_pack(pack_id: StringName) -> void:
	if _scrolled_since_press(): return
	var pack := CardDB.get_pack(pack_id)
	if pack == null:
		return
	# TODO(server): neskor JEDEN request purchase_pack(pack_id) — server overi cenu, strhne,
	# zrolluje a vrati vysledok + novu penazenku (apply_wallet_snapshot). Lokalne je to spend -> roll -> grant.
	if not PlayerProfile.try_spend_currency(pack.currency, pack.price, "pack:%s" % pack_id):
		_show_shop_message("Not enough %s" % pack.currency)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rolled := PackRoller.roll(pack, rng, CardDB.get_pack_pool(pack.faction))

	# NEW sa urcuje PRED grantom; id padnute 2x v jednom balicku je NEW len prvy raz
	var is_new: Array[bool] = []
	var seen := {}
	for id in rolled:
		var owned := PlayerProfile.owns_card(id) or PlayerProfile.owns_hero(id)
		is_new.append(not owned and not seen.has(id))
		seen[id] = true

	PlayerProfile.grant_cards(rolled)
	DebugLog.info("pack", "%s -> %s" % [pack_id, rolled])

	reveal.show_result(pack.display_name, rolled, is_new)
	shop_scroll.visible = false

# --- Ceny + sprava ---

# Ikona meny vlavo od textu ceny. Neznama mena (free) -> bez ikony.
func _set_price_icon(button: Button, currency: StringName) -> void:
	var tex: Texture2D = CURRENCY_ICONS.get(currency)
	if tex == null:
		return
	button.icon = tex
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", PRICE_ICON_WIDTH)

func _refresh_price_colors() -> void:
	for button in _buy_buttons:
		if is_instance_valid(button):
			_refresh_buy_button(button, _buy_buttons[button])
	for button in _offer_buttons:
		if is_instance_valid(button):
			var info: Dictionary = _offer_buttons[button]
			_apply_price_color(button, PlayerProfile.can_afford(info["currency"], info["price"]))

# Cervena cena = nestaci zostatok. Tlacidlo ostava tapnutelne (ukaze "Not enough").
func _refresh_buy_button(button: Button, pack: PackData) -> void:
	var affordable := pack.price <= 0 or PlayerProfile.can_afford(pack.currency, pack.price)
	_apply_price_color(button, affordable)

func _apply_price_color(button: Button, affordable: bool) -> void:
	var color := PRICE_COLOR if affordable else UNAFFORDABLE
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, color)

# Kratka sprava v strede viditelnej plochy shopu (balicky mozu byt odscrollovane);
# opakovane volanie ju restartuje.
func _show_shop_message(text: String) -> void:
	if _message_label == null:
		_message_label = _make_label("", 18, GOLD, 4)
		_message_label.add_theme_font_override("font", BOLD_FONT)
		_message_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_message_label.z_index = 1
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.04, 0.08, 0.85)
		sb.border_color = Color(0.85, 0.68, 0.3, 0.8)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		_message_label.add_theme_stylebox_override("normal", sb)
		add_child(_message_label)
	_message_label.text = text
	_message_label.reset_size()
	_message_label.global_position = get_global_rect().get_center() - _message_label.size / 2
	_message_label.modulate.a = 1.0
	_message_label.visible = true
	if _message_tween != null:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(MESSAGE_HOLD)
	_message_tween.tween_property(_message_label, "modulate:a", 0.0, MESSAGE_FADE)
	_message_tween.tween_callback(_message_label.hide)

# --- Art + styling helpers ---

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

# Text kresli obycajny Button (nie TextureButton); malba je "Art" ScaledNinePatch za nim.
func _style_shop_button(button: Button, currency: StringName) -> void:
	var path: String = BUTTON_PATHS.get(currency, BUTTON_PATHS[&"free"])
	var tex := _texture_or_null(path)
	_guard_shop_button(button)
	button.add_theme_font_override("font", BOLD_FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.85))
	button.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.78))
	button.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0))
	button.add_theme_constant_override("outline_size", 3)

	var art := button.get_node_or_null("Art") as ScaledNinePatch
	if tex != null:
		# Texturovy stylebox drzi okraje v plnej velkosti -> na 30 px tlacidle
		# by zjedli celu vysku. Art kresli ScaledNinePatch (rohy sa zmensia),
		# stylebox je prazdny a Button kresli len text.
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxEmpty.new()
			sb.content_margin_left = BUTTON_MARGIN_X
			sb.content_margin_right = BUTTON_MARGIN_X
			sb.content_margin_top = BUTTON_MARGIN_Y
			sb.content_margin_bottom = BUTTON_MARGIN_Y
			button.add_theme_stylebox_override(state, sb)
		if art == null:
			art = ScaledNinePatch.new()
			art.name = "Art"
			art.show_behind_parent = true   # inak by art prekryl text tlacidla
			button.add_child(art)
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			button.button_down.connect(_refresh_button_art.bind(button))
			button.button_up.connect(_refresh_button_art.bind(button))
			# Button sa prekresli aj pri zmene disabled -> funguje aj ked sa
			# disabled nastavi az po stylovani
			button.draw.connect(_refresh_button_art.bind(button))
		art.texture = tex
		art.patch_margin_left = BUTTON_PATCH_X
		art.patch_margin_right = BUTTON_PATCH_X
		art.patch_margin_top = BUTTON_PATCH_Y
		art.patch_margin_bottom = BUTTON_PATCH_Y
		art.patch_scale = 0.0
		art.draw_center = true
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_refresh_button_art(button)
		return

	if art != null:
		# predosly styl s artom — placeholder ho nahradza
		button.remove_child(art)
		art.queue_free()

	var base: Color = PLACEHOLDER_COLORS.get(currency, PLACEHOLDER_COLORS[&"free"])
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = base
		match state:
			"hover":
				sb.bg_color = base.lightened(0.15)
			"pressed":
				sb.bg_color = base.darkened(0.25)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = BUTTON_MARGIN_X
		sb.content_margin_right = BUTTON_MARGIN_X
		sb.content_margin_top = BUTTON_MARGIN_Y
		sb.content_margin_bottom = BUTTON_MARGIN_Y
		button.add_theme_stylebox_override(state, sb)
	button.tooltip_text = path.get_file()

# Stav tlacidla na arte: disabled sivy, drzane tmavsie, inak normal.
func _refresh_button_art(button: Button) -> void:
	var art := button.get_node_or_null("Art") as CanvasItem
	if art == null:
		return
	if button.disabled:
		art.self_modulate = Color(0.5, 0.5, 0.5)
	elif button.get_draw_mode() == BaseButton.DRAW_PRESSED or button.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED:
		art.self_modulate = Color(0.8, 0.8, 0.8)
	else:
		art.self_modulate = Color.WHITE

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

func _fill_holder(holder: Control, child: Control) -> void:
	holder.add_child(child)
	child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _free_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
