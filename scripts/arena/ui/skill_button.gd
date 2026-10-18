extends Button
class_name SkillButton

# SkillButton — tap-to-fire aktivneho skillu lokalneho boha. Sedy s odpoctom
# sekund = cooldown, zlaty s menom skillu = ready. Disabled kym je boh mrtvy.
# Boh bez skillu / s neimplementovanym skillom = button skryty.
# PLACEHOLDER vzhlad (kruh + text, rovnako ako SynergyIcon) — art pride neskor.
# process_mode = PAUSABLE v HUD.tscn — HUD root je WHEN_PAUSED a pollujuci
# child by inak pocas hry zamrzol (architecture.md §6, ako EnergyBar).

const COOLDOWN_TINT := Color(0.45, 0.45, 0.45)
const READY_TINT := Color(1.0, 0.85, 0.35)

@onready var label: Label = $Label

var _hero: Node = null
var _skill: SkillData = null

func _ready() -> void:
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	circle.set_corner_radius_all(38)
	circle.set_border_width_all(2)
	circle.border_color = Color(0.9, 0.9, 0.9)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, circle)
	visible = false
	pressed.connect(_on_pressed)

# Volane raz z arena.gd po spawn_hero("player"). Skill sa pocas zapasu nemeni.
func configure(hero: Node) -> void:
	_hero = hero
	_skill = null
	if hero != null and "skill" in hero:
		_skill = hero.skill
	visible = SkillEffects.is_implemented(_skill)

func _process(_delta: float) -> void:
	if not visible or _hero == null or not is_instance_valid(_hero):
		return
	disabled = _hero.is_dead
	var cd: float = _hero.get_skill_cooldown_left()
	var tint := READY_TINT if cd <= 0.0 else COOLDOWN_TINT
	self_modulate = tint
	label.modulate = tint
	label.text = _skill.display_name if cd <= 0.0 else str(ceili(cd))

func _on_pressed() -> void:
	if _hero != null and is_instance_valid(_hero):
		_hero.try_cast_skill()
