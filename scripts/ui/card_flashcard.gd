extends Control
class_name CardFlashcard

# CardFlashcard — detail boha/karty (SWFA unit-detail styl): art, level,
# progres kopii, popis a staty s nahladom "cur > next" pre staty ktore
# skaluju s levelom. Level up je MANUALNY — jedine volanie
# PlayerProfile.upgrade_card(). Samostatna scena, aby ju neskor mohli
# otvarat aj ine obrazovky; zatial ju otvara len EncyclopediaOverlay.

signal closed

# Text tlacidla na jednom mieste — tematicky nazov sa vyberie neskor.
const LEVEL_UP_LABEL := "Level up"
const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Unique"]
# Poradie musi sediet s unit.gd TargetFilter { ALL, UNITS_ONLY, STRUCTURES_ONLY }.
const TARGET_NAMES := ["All", "Units", "Structures"]

@onready var picture: TextureRect = $Card/Margin/Layout/Left/Picture
@onready var level_label: Label = $Card/Margin/Layout/Left/LevelLabel
@onready var copies_bar: ProgressBar = $Card/Margin/Layout/Left/CopiesBar
@onready var copies_label: Label = $Card/Margin/Layout/Left/CopiesLabel
@onready var level_up_button: Button = $Card/Margin/Layout/Left/LevelUpButton
@onready var name_label: Label = $Card/Margin/Layout/Right/Header/NameLabel
@onready var close_button: Button = $Card/Margin/Layout/Right/Header/CloseButton
@onready var meta_label: Label = $Card/Margin/Layout/Right/MetaLabel
@onready var description_label: Label = $Card/Margin/Layout/Right/DescriptionLabel
@onready var stats_grid: GridContainer = $Card/Margin/Layout/Right/StatsGrid

var _id: StringName = &""
var _kind: StringName = DeckTile.KIND_CARD

func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	level_up_button.pressed.connect(_on_level_up_pressed)

func open_for(id: StringName, kind: StringName) -> void:
	_id = id
	_kind = kind
	_refresh()
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func _on_level_up_pressed() -> void:
	if PlayerProfile.upgrade_card(_id):
		_refresh()

func _refresh() -> void:
	var is_hero := _kind == DeckTile.KIND_HERO
	var owned := PlayerProfile.owns_hero(_id) if is_hero else PlayerProfile.owns_card(_id)
	# nevlastnene sa zobrazuje ako level 1
	var level := 1
	var copies := 0
	if owned:
		level = PlayerProfile.get_hero_level(_id) if is_hero else PlayerProfile.get_card_level(_id)
		copies = PlayerProfile.get_hero_copies(_id) if is_hero else PlayerProfile.get_card_copies(_id)
	var need := PlayerProfile.get_copies_to_next(_id)
	var at_max := owned and need < 0
	var show_next := owned and need >= 0

	for child in stats_grid.get_children():
		child.queue_free()
	picture.texture = null
	name_label.text = String(_id)
	meta_label.text = ""
	var description := ""

	if is_hero:
		var hero: HeroData = CardDB.get_hero(_id) if CardDB.has_hero(_id) else null
		if hero != null:
			picture.texture = _hero_texture(hero)
			name_label.text = hero.display_name
			description = hero.description
			meta_label.text = "God · %s" % _rarity_name(hero.rarity)
			_fill_hero_stats(hero, level, show_next)
	else:
		var card: CardData = CardDB.get_card(_id) if CardDB.has_card(_id) else null
		if card != null:
			picture.texture = card.scroll_texture
			name_label.text = card.display_name
			description = card.description
			meta_label.text = "%s · %s · Cost %d" % [_card_type(card), _rarity_name(card.rarity), card.cost]
			if card.unit_data != null:
				_fill_unit_stats(card, level, show_next)
			elif card.spell_data != null:
				_fill_spell_stats(card.spell_data, level, show_next)

	description_label.text = description
	description_label.visible = description != ""

	level_label.text = "Lv %d" % level if owned else "Locked"

	if not owned:
		copies_bar.visible = false
		copies_label.text = ""
	elif at_max:
		copies_bar.visible = true
		copies_bar.max_value = 1
		copies_bar.value = 1
		copies_label.text = "MAX"
	else:
		copies_bar.visible = true
		copies_bar.max_value = need
		copies_bar.value = mini(copies, need)
		copies_label.text = "%d / %d" % [copies, need]

	level_up_button.text = LEVEL_UP_LABEL
	level_up_button.visible = owned and not at_max
	level_up_button.disabled = not PlayerProfile.can_upgrade(_id)

# --- Staty ---

func _fill_unit_stats(card: CardData, level: int, show_next: bool) -> void:
	var unit := card.unit_data
	_add_stat("Health", _scaled(unit.max_hp, level, show_next))
	_add_stat("Damage", _scaled(unit.damage, level, show_next))
	_add_stat("Attack cooldown", "%.1fs" % unit.attack_cooldown)
	_add_stat("Move speed", "%d" % roundi(unit.speed))
	_add_stat("Range", "%d" % roundi(unit.attack_range))
	_add_stat("Attack", "Melee" if unit.attack_type == UnitData.AttackType.MELEE else "Ranged")
	var target := unit.target_filter
	_add_stat("Target", TARGET_NAMES[target] if target >= 0 and target < TARGET_NAMES.size() else "?")
	if card.unit_count > 1:
		_add_stat("Squad size", "%d" % card.unit_count)

func _fill_spell_stats(spell: SpellData, level: int, show_next: bool) -> void:
	if spell.damage > 0:
		_add_stat("Damage", _scaled(spell.damage, level, show_next))
	_add_stat("Radius", "%d" % roundi(spell.radius))
	_add_stat("Cast time", "%.1fs" % spell.cast_time)
	if spell.zone_duration > 0.0:
		_add_stat("Zone duration", "%.1fs" % spell.zone_duration)
	_add_stat("Effect duration", "%.1fs" % spell.effect_duration)

func _fill_hero_stats(hero: HeroData, level: int, show_next: bool) -> void:
	_add_stat("Health", _scaled(hero.max_hp, level, show_next))
	_add_stat("Damage", _scaled(hero.projectile_damage, level, show_next))
	# rychlost utoku skaluje opacne — kratsi recovery (rovnako ako player.gd)
	var recovery := "%.2fs" % _hero_recovery(hero, level)
	if show_next:
		recovery += " > %.2fs" % _hero_recovery(hero, level + 1)
	_add_stat("Attack recovery", recovery)
	_add_stat("Move speed", "%d" % roundi(hero.speed))
	_add_stat("Range", "%d" % roundi(hero.attack_range))
	if hero.domain != &"":
		_add_stat("Domain", String(hero.domain).capitalize())

# Rovnaky vzorec ako unit.gd / player.gd / spell_zone.gd v zapase.
func _scaled(base: int, level: int, show_next: bool) -> String:
	var curve := PlayerProfile.LEVEL_CURVE
	var cur := roundi(base * curve.get_stat_multiplier(level))
	if not show_next:
		return "%d" % cur
	var next := roundi(base * curve.get_stat_multiplier(level + 1))
	return "%d > %d" % [cur, next]

func _hero_recovery(hero: HeroData, level: int) -> float:
	var curve := PlayerProfile.LEVEL_CURVE
	return hero.recovery_time / maxf(curve.get_hero_attack_speed_multiplier(level), 0.01)

func _add_stat(stat_name: String, value: String) -> void:
	var label := Label.new()
	label.text = "%s: %s" % [stat_name, value]
	stats_grid.add_child(label)

# --- Pomocne ---

func _card_type(card: CardData) -> String:
	if card.spell_data != null:
		return "Spell"
	return "Squad" if card.unit_count > 1 else "Unit"

func _rarity_name(rarity: int) -> String:
	return RARITY_NAMES[rarity] if rarity >= 0 and rarity < RARITY_NAMES.size() else "?"

# Rovnaky guard ako DeckTile._hero_texture — obaja bohovia maju "iddle_left".
func _hero_texture(hero: HeroData) -> Texture2D:
	var frames := hero.sprite_frames
	if frames == null:
		return null
	for anim in [&"iddle_left", &"idle_left"]:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			return frames.get_frame_texture(anim, 0)
	return null
