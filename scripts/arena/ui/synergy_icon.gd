extends Button
class_name SynergyIcon

# SynergyIcon — maly okruhly indikator synergy nad rukou. Sedy = podmienka
# balicka nie je splnena, zlaty a pulzujuci = splnena. Tap ukaze tooltip s
# poctom a bonusmi. Stav sa pocas zapasu NEMENI (zavisi len od balicka),
# preto staci jedno configure() po nastaveni manifestu v arena.gd.
# PLACEHOLDER vzhlad (kruh + cislo) — realny art pride neskor.

const INACTIVE_TINT := Color(0.45, 0.45, 0.45)
const ACTIVE_TINT := Color(1.0, 0.85, 0.35)
const TOOLTIP_SECONDS := 4.0

@onready var count_label: Label = $CountLabel
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_label: Label = $Tooltip/TooltipLabel

var _pulse_tween: Tween
# Token ako _toast_token v main_menu.gd — starsi timer neschova novsi tap.
var _tooltip_token := 0

func _ready() -> void:
	# Jeden okruhly StyleBoxFlat pre vsetky stavy — Button je len kruh.
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	circle.set_corner_radius_all(28)
	circle.set_border_width_all(2)
	circle.border_color = Color(0.9, 0.9, 0.9)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, circle)
	visible = false
	pressed.connect(_on_pressed)

func configure(team: String) -> void:
	var status := BattleManager.get_synergy_status(team)
	if status.is_empty():
		return
	var hero := BattleManager.get_team_hero_data(team)
	if hero == null:
		return
	var active: bool = status["active"]
	count_label.text = "%d/%d" % [status["have"], status["need"]]
	tooltip_label.text = "%s %d / %d — %s\n%s" % [
		String(status["tag"]).capitalize(), status["have"], status["need"],
		"active" if active else "not active", DeckRules.describe_synergy(hero)]

	# Tint len kruh + cislo: self_modulate sa NEsiri na deti, tooltip ostava cisty.
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	var tint := ACTIVE_TINT if active else INACTIVE_TINT
	self_modulate = tint
	count_label.modulate = tint
	if active:
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(self, "self_modulate", ACTIVE_TINT.lightened(0.35), 0.8)
		_pulse_tween.tween_property(self, "self_modulate", ACTIVE_TINT, 0.8)
	visible = true

func _on_pressed() -> void:
	tooltip.visible = not tooltip.visible
	if not tooltip.visible:
		return
	# Rastie hore a dolava od ikony (ikona sedi vpravo dole pri ruke).
	tooltip.reset_size()
	tooltip.position = Vector2(size.x - tooltip.size.x, -tooltip.size.y - 6.0)
	_tooltip_token += 1
	var token := _tooltip_token
	get_tree().create_timer(TOOLTIP_SECONDS).timeout.connect(func():
		if token == _tooltip_token:
			tooltip.visible = false
	)
