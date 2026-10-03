extends Control
class_name ShopOverlay

# ShopOverlay — zoznam balickov -> otvorenie -> reveal ako jednoduchy zoznam.
# Rovnaky overlay pattern ako CreditsOverlay (open()/close(), signal closed).
# Losovanie robi cisty PackRoller; zbierku meni LEN PlayerProfile.grant_cards().
# Ziadna mena, ziadne animacie — placeholder UI s default temou.

signal closed

const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Unique"]

@onready var close_button: Button = $ShopPanel/Margin/Content/Header/CloseButton
@onready var pack_list: VBoxContainer = $ShopPanel/Margin/Content/PackList
@onready var reveal_box: VBoxContainer = $ShopPanel/Margin/Content/RevealBox
@onready var reveal_title: Label = $ShopPanel/Margin/Content/RevealBox/RevealTitle
@onready var reveal_list: HBoxContainer = $ShopPanel/Margin/Content/RevealBox/RevealScroll/RevealList
@onready var reveal_ok_button: Button = $ShopPanel/Margin/Content/RevealBox/RevealOkButton

func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	reveal_ok_button.pressed.connect(_show_pack_list)

func open() -> void:
	for child in pack_list.get_children():
		child.queue_free()
	for pack_id in CardDB.list_pack_ids():
		var pack := CardDB.get_pack(pack_id)
		if pack == null:
			continue
		var price_text := "FREE" if pack.price <= 0 else "%d" % pack.price
		var button := Button.new()
		button.text = "%s — %d scrolls — %s" % [pack.display_name, pack.card_count, price_text]
		button.custom_minimum_size.y = 56
		button.pressed.connect(_open_pack.bind(pack_id))
		pack_list.add_child(button)
	_show_pack_list()
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func _show_pack_list() -> void:
	pack_list.visible = true
	reveal_box.visible = false

func _open_pack(pack_id: StringName) -> void:
	var pack := CardDB.get_pack(pack_id)
	if pack == null:
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
	print("[pack] %s -> %s" % [pack_id, rolled])

	for child in reveal_list.get_children():
		child.queue_free()
	for i in rolled.size():
		reveal_list.add_child(_build_reveal_entry(rolled[i], is_new[i]))

	reveal_title.text = pack.display_name if not rolled.is_empty() else "Nothing to reveal"
	pack_list.visible = false
	reveal_box.visible = true

func _build_reveal_entry(id: StringName, is_new: bool) -> Control:
	var display_name := String(id)
	var rarity := 0
	var texture: Texture2D = null
	if CardDB.has_card(id):
		var card := CardDB.get_card(id)
		display_name = card.display_name
		rarity = card.rarity
		texture = card.scroll_texture
	elif CardDB.has_hero(id):
		# bohovia zatial nemaju scroll art — obrazok ostane prazdny
		var hero := CardDB.get_hero(id)
		display_name = hero.display_name
		rarity = hero.rarity

	var entry := VBoxContainer.new()
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(120, 144)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = texture
	entry.add_child(picture)

	var name_label := Label.new()
	name_label.text = display_name
	entry.add_child(name_label)

	var rarity_label := Label.new()
	rarity_label.text = RARITY_NAMES[rarity] if rarity >= 0 and rarity < RARITY_NAMES.size() else "?"
	entry.add_child(rarity_label)

	var status_label := Label.new()
	status_label.text = "NEW" if is_new else "+1 copy"
	entry.add_child(status_label)
	return entry
