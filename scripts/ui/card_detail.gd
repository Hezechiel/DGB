extends Control
class_name CardDetail

# CardDetail — detail boha/karty na novom arte (ramik + sceneria panteonu).
# Nahrada starej flashcard sceny s rovnakym API: open_for(id, kind), close(),
# closed. Vzorce statov su prenesene bez zmeny. Level up je MANUALNY —
# jedine volanie PlayerProfile.upgrade_card().
# Card Detail screen on the new art; same API and stat formulas as the old
# flashcard. Vzhlad ide z dgb_theme.tres (nastaveny len na tomto roote).

signal closed

const STAT_TILE_SCENE := preload("res://scenes/menu/stat_tile.tscn")
const DETAILS_FONT := preload("res://assets/fonts/Oswald/static/Oswald-Regular.ttf")
const DETAILS_FONT_SIZE := 13

const RARITY_NAMES := ["Common", "Rare", "Epic", "Legendary", "Unique"]
# Farba hodnoty rarity, index = rarity. / Rarity value color by index.
const RARITY_COLORS := [
	Color(0.75, 0.75, 0.78),
	Color(0.35, 0.6, 1.0),
	Color(0.7, 0.4, 1.0),
	Color(1.0, 0.6, 0.15),
	Color(1.0, 0.82, 0.3),
]
# Poradie musi sediet s unit.gd TargetFilter { ALL, UNITS_ONLY, STRUCTURES_ONLY }.
const TARGET_NAMES := ["All", "Units", "Structures"]
# SpellData.spell_type 0/1/2 -> efekt. / Spell effect by spell_type.
const EFFECT_NAMES := ["Slow", "Stun", "Root"]
# CardData/HeroData.obtain_source 0..4.
const OBTAIN_NAMES := ["None", "Pack", "Achievement", "Quest", "Event"]
# Sceneria panteonu za popisom; chybajuci kluc = ziadna. / Faction scenery art.
const FACTION_THEME_ART := {
	&"greek": "res://assets/menu/deck/themes/greek_theme.png",
	&"norse": "res://assets/menu/deck/themes/nordic_theme.png",
}
const NOT_OWNED_MODULATE := Color(0.45, 0.45, 0.45)
const CLOSE_PRESSED_MODULATE := Color(0.75, 0.75, 0.75)

@onready var frame_root: Control = $FrameFit/FrameRoot
@onready var theme_art: TextureRect = $FrameFit/FrameRoot/ThemeArt
@onready var card_art: TextureRect = $FrameFit/FrameRoot/CardArt
@onready var level_label: Label = $FrameFit/FrameRoot/LevelBadge/LevelLabel
@onready var name_label: Label = $FrameFit/FrameRoot/InfoColumn/Header/NameBlock/NameLabel
@onready var type_tile: StatTile = $FrameFit/FrameRoot/InfoColumn/Header/TypeTile
@onready var rarity_tile: StatTile = $FrameFit/FrameRoot/InfoColumn/Header/RarityTile
@onready var description_label: Label = $FrameFit/FrameRoot/InfoColumn/DescriptionRow/DescriptionLabel
@onready var stats_grid: GridContainer = $FrameFit/FrameRoot/InfoColumn/StatsGrid
@onready var skills_tab: Button = $FrameFit/FrameRoot/TabsColumn/TabsRow/SkillsTab
@onready var details_tab: Button = $FrameFit/FrameRoot/TabsColumn/TabsRow/DetailsTab
# ScrollContainer okolo SkillsPane — viditelnost tabu prepina tento uzol,
# rovnako ako details_scroll. / Toggled by the tab, like details_scroll.
@onready var skills_pane: Control = $FrameFit/FrameRoot/TabsColumn/TabContent/SkillsScroll
@onready var skill_name_label: Label = $FrameFit/FrameRoot/TabsColumn/TabContent/SkillsScroll/SkillsPane/SkillRow/SkillText/SkillName
@onready var skill_description_label: Label = $FrameFit/FrameRoot/TabsColumn/TabContent/SkillsScroll/SkillsPane/SkillRow/SkillText/SkillDescription
@onready var details_scroll: ScrollContainer = $FrameFit/FrameRoot/TabsColumn/TabContent/DetailsScroll
@onready var details_pane: VBoxContainer = $FrameFit/FrameRoot/TabsColumn/TabContent/DetailsScroll/DetailsPane
@onready var upgrade_title: Label = $FrameFit/FrameRoot/UpgradePanel/UpgradeTitle
@onready var level_step_label: Label = $FrameFit/FrameRoot/UpgradePanel/LevelStepLabel
@onready var copies_bar: ProgressBar = $FrameFit/FrameRoot/UpgradePanel/CopiesBar
@onready var copies_label: Label = $FrameFit/FrameRoot/UpgradePanel/CopiesLabel
@onready var upgrade_button: Button = $FrameFit/FrameRoot/UpgradePanel/UpgradeButton
@onready var close_button: TextureButton = $FrameFit/FrameRoot/CloseButton

var _id: StringName = &""
var _kind: StringName = DeckTile.KIND_CARD
var _press_outside: bool = false   # tap mimo panelu sa zacal mimo neho

func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	# vizualna odozva stlacenia X / pressed feedback
	close_button.button_down.connect(func() -> void: close_button.self_modulate = CLOSE_PRESSED_MODULATE)
	close_button.button_up.connect(func() -> void: close_button.self_modulate = Color.WHITE)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	skills_tab.toggled.connect(_on_tab_toggled)
	details_tab.toggled.connect(_on_tab_toggled)
	PlayerProfile.profile_changed.connect(_on_profile_changed)
	_update_tabs()

func open_for(id: StringName, kind: StringName) -> void:
	_id = id
	_kind = kind
	# kazde otvorenie zacina na Skills / every open starts on Skills
	skills_tab.button_pressed = true
	_refresh()
	visible = true

func close() -> void:
	visible = false
	_press_outside = false
	closed.emit()

# Tap mimo panelu (na stmavene pozadie) = rovnako ako X. Dim / FrameFit /
# FrameRoot su MOUSE_FILTER_IGNORE, takze klik mimo ovladacich prvkov padne
# sem na root. Zatvara sa az na pustenie a len ked aj stlacenie bolo mimo
# panelu (tah zvnutra panelu von nezatvori). Len mouse eventy — dotyk ich
# emuluje. / Tap outside the panel closes like the X button.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var outside := not frame_root.get_global_rect().has_point(event.global_position)
	if event.pressed:
		_press_outside = outside
	elif _press_outside and outside:
		_press_outside = false
		accept_event()
		close()
	else:
		_press_outside = false

func _on_profile_changed() -> void:
	if visible:
		_refresh()

func _on_upgrade_pressed() -> void:
	if PlayerProfile.upgrade_card(_id):
		_refresh()

func _on_tab_toggled(_pressed: bool) -> void:
	_update_tabs()

# Viditelny je len panel stlaceneho tabu. / Only the pressed tab's pane shows.
func _update_tabs() -> void:
	skills_pane.visible = skills_tab.button_pressed
	details_scroll.visible = details_tab.button_pressed

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

	_clear(stats_grid)
	_clear(details_pane)
	card_art.texture = null
	name_label.text = String(_id)
	type_tile.set_stat("Type", "?")
	rarity_tile.set_stat("Rarity", "?")
	var description := ""
	var faction: StringName = &""
	# Skills tab: bez skillu pomlcka / no skill -> dash
	skill_name_label.text = "—"
	skill_description_label.text = ""

	if is_hero:
		var hero: HeroData = CardDB.get_hero(_id) if CardDB.has_hero(_id) else null
		if hero != null:
			card_art.texture = hero.card_art if hero.card_art != null else _hero_texture(hero)
			name_label.text = hero.display_name
			description = hero.description
			faction = hero.faction
			type_tile.set_stat("Type", "God")
			_set_rarity(hero.rarity)
			_fill_hero_stats(hero, level, show_next)
			_fill_skill(hero.skill)
			_fill_details(hero.faction, hero.domain, [], hero.obtain_source)
			var synergy := DeckRules.describe_synergy(hero)
			if synergy != "":
				_add_detail("Synergy: %s" % synergy)
	else:
		var card: CardData = CardDB.get_card(_id) if CardDB.has_card(_id) else null
		if card != null:
			card_art.texture = card.scroll_texture
			name_label.text = card.display_name
			description = card.description
			faction = card.faction
			type_tile.set_stat("Type", _card_type(card))
			_set_rarity(card.rarity)
			_fill_details(card.faction, card.domain, card.tags, card.obtain_source)
			if card.unit_data != null:
				_fill_unit_stats(card, level, show_next)
				if card.unit_data.unit_count > 1:
					_add_detail("Deploy Time: UNK")
			elif card.spell_data != null:
				_fill_spell_stats(card, level, show_next)

	description_label.text = description
	_set_theme_art(faction)
	card_art.modulate = Color.WHITE if owned else NOT_OWNED_MODULATE
	level_label.text = "%d" % level if owned else "—"
	_refresh_upgrade(owned, at_max, level, copies, need)

# --- Skills tab ---

# Text ide zo SkillData.get_description() — cisla sa ladia len v .tres.
# Text comes from the skill's template; numbers are tuned only in its .tres.
func _fill_skill(skill: SkillData) -> void:
	if skill == null:
		return
	skill_name_label.text = skill.display_name
	skill_description_label.text = "Cooldown: %ss\n%s" % [SkillData.format_number(skill.cooldown), skill.get_description()]

# --- Upgrade box ---

func _refresh_upgrade(owned: bool, at_max: bool, level: int, copies: int, need: int) -> void:
	upgrade_title.text = "Upgrade" if owned else "Locked"
	level_step_label.visible = owned
	copies_bar.visible = owned and not at_max
	copies_label.visible = owned and not at_max
	upgrade_button.visible = owned and not at_max
	if not owned:
		return
	if at_max:
		level_step_label.text = "Max level"
		return
	level_step_label.text = "Lv. %d → Lv. %d" % [level, level + 1]
	copies_bar.max_value = need
	copies_bar.value = mini(copies, need)
	copies_label.text = "%d / %d copies" % [copies, need]
	upgrade_button.disabled = not PlayerProfile.can_upgrade(_id)

# --- Staty ---

func _fill_hero_stats(hero: HeroData, level: int, show_next: bool) -> void:
	_add_scaled("Health", hero.max_hp, level, show_next)
	_add_scaled("Attack Power", hero.projectile_damage, level, show_next)
	# rychlost utoku skaluje opacne — kratsi recovery (rovnako ako player.gd),
	# delta je preto zaporna / faster attacks = shorter recovery, negative delta
	var recovery := _hero_recovery(hero, level)
	var recovery_delta := ""
	if show_next:
		var diff := _hero_recovery(hero, level + 1) - recovery
		if absf(diff) >= 0.005:
			recovery_delta = "%+.2fs" % diff
	_add_stat("Attack Speed", "%.2fs" % recovery, recovery_delta)
	_add_stat("Movement Speed", "%d" % roundi(hero.speed))
	_add_stat("Attack Range", "%d" % roundi(hero.attack_range))
	_add_stat("Attack Type", "Melee" if hero.attack_type == HeroData.AttackType.MELEE else "Ranged")
	_add_stat("Domain", String(hero.domain).capitalize() if hero.domain != &"" else "—")
	_add_stat("Energy Cost", "—")

func _fill_unit_stats(card: CardData, level: int, show_next: bool) -> void:
	var unit := card.unit_data
	_add_scaled("Health", unit.max_hp, level, show_next)
	_add_scaled("Attack Power", unit.damage, level, show_next)
	_add_stat("Attack Speed", "%.1fs" % unit.attack_cooldown)
	_add_stat("Movement Speed", "%d" % roundi(unit.speed))
	_add_stat("Attack Range", "%d" % roundi(unit.attack_range))
	var target := unit.target_filter
	_add_stat("Target", TARGET_NAMES[target] if target >= 0 and target < TARGET_NAMES.size() else "?")
	# squad: velkost oddielu namiesto Deploy Time (ten ide do Details)
	if unit.unit_count > 1:
		_add_stat("Squad Size", "%d" % unit.unit_count)
	else:
		_add_stat("Deploy Time", "UNK")
	_add_stat("Energy Cost", "%d" % card.cost)

func _fill_spell_stats(card: CardData, level: int, show_next: bool) -> void:
	var spell := card.spell_data
	if spell.damage > 0:
		_add_scaled("Damage", spell.damage, level, show_next)
	else:
		_add_stat("Damage", "—")
	_add_stat("Radius", "%d" % roundi(spell.radius))
	_add_stat("Cast Time", "%.1fs" % spell.cast_time)
	_add_stat("Zone Duration", "%.1fs" % spell.zone_duration if spell.zone_duration > 0.0 else "Instant")
	_add_stat("Effect Duration", "%.1fs" % spell.effect_duration)
	var effect := spell.spell_type
	_add_stat("Effect", EFFECT_NAMES[effect] if effect >= 0 and effect < EFFECT_NAMES.size() else "?")
	_add_stat("Target", "Enemies")
	_add_stat("Energy Cost", "%d" % card.cost)

# Stat ktory skaluje s levelom: hodnota = aktualny level, delta "+N" k dalsiemu.
# Level-scaled stat: value = current level, delta "+N" to the next level.
func _add_scaled(stat_name: String, base: int, level: int, show_next: bool) -> void:
	var cur := _scaled_value(base, level)
	var delta := ""
	if show_next:
		delta = "+%d" % (_scaled_value(base, level + 1) - cur)
	_add_stat(stat_name, "%d" % cur, delta)

# Rovnaky vzorec ako unit.gd / player.gd / spell_zone.gd v zapase.
func _scaled_value(base: int, level: int) -> int:
	return roundi(base * PlayerProfile.LEVEL_CURVE.get_stat_multiplier(level))

func _hero_recovery(hero: HeroData, level: int) -> float:
	var curve := PlayerProfile.LEVEL_CURVE
	return hero.recovery_time / maxf(curve.get_hero_attack_speed_multiplier(level), 0.01)

func _add_stat(stat_name: String, value: String, delta: String = "") -> void:
	var tile: StatTile = STAT_TILE_SCENE.instantiate()
	stats_grid.add_child(tile)
	tile.set_stat(stat_name, value, delta)

# --- Details tab ---

func _fill_details(faction: StringName, domain: StringName, tags: Array, obtain_source: int) -> void:
	_add_detail("Pantheon: %s" % (String(faction).capitalize() if faction != &"" else "—"))
	_add_detail("Domain: %s" % (String(domain).capitalize() if domain != &"" else "—"))
	var tag_names: Array[String] = []
	for tag in tags:
		tag_names.append(String(tag).capitalize())
	_add_detail("Tags: %s" % (", ".join(tag_names) if not tag_names.is_empty() else "—"))
	var source: String = OBTAIN_NAMES[obtain_source] if obtain_source >= 0 and obtain_source < OBTAIN_NAMES.size() else "?"
	_add_detail("Obtained from: %s" % source)

func _add_detail(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override(&"font", DETAILS_FONT)
	label.add_theme_font_size_override(&"font_size", DETAILS_FONT_SIZE)
	details_pane.add_child(label)

# --- Pomocne ---

func _set_rarity(rarity: int) -> void:
	rarity_tile.set_stat("Rarity", _rarity_name(rarity))
	if rarity >= 0 and rarity < RARITY_COLORS.size():
		rarity_tile.set_value_color(RARITY_COLORS[rarity])

func _set_theme_art(faction: StringName) -> void:
	var path: String = FACTION_THEME_ART.get(faction, "")
	theme_art.texture = load(path) if path != "" and ResourceLoader.exists(path) else null
	theme_art.visible = theme_art.texture != null

# remove_child hned, aby stare dlazdice neostali v layoute do konca framu.
# Detach immediately so stale children don't linger in the layout this frame.
func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _card_type(card: CardData) -> String:
	if card.spell_data != null:
		return "Spell"
	return "Squad" if card.unit_data.unit_count > 1 else "Unit"

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
