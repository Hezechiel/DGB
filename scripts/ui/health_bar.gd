extends Control

# Set to true for player-controlled characters (bar always visible).
# Set to false for enemies and turrets (bar hidden at full HP).
@export var always_visible: bool = false

# Team color palette — add new teams here when needed (e.g. "coop" for future blue).
const TEAM_COLORS: Dictionary = {
	"player": Color(0.15, 0.85, 0.2),   # green
	"enemy":  Color(0.9,  0.15, 0.15),  # red
	"coop":   Color(0.15, 0.5,  0.95),  # blue  (future, not used yet)
}

var _max_hp: int = 1
var _current_hp: int = 1
var _tween: Tween = null

@onready var bar: ProgressBar = $Bar


func _ready() -> void:
	if not always_visible:
		visible = false


# Call once from parent _ready() after hp vars are set.
func init(max_value: int, team_name: String) -> void:
	_max_hp = max_value
	_current_hp = max_value
	bar.max_value = float(max_value)
	bar.value    = float(max_value)
	_apply_team_color(team_name)
	if not always_visible:
		visible = false


# Call after every HP change (take_damage, heal).
func set_health(new_hp: int) -> void:
	_current_hp = clampi(new_hp, 0, _max_hp)

	# Show/hide
	if always_visible:
		visible = true
	else:
		visible = _current_hp < _max_hp and _current_hp > 0

	# Smooth tween
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(bar, "value", float(_current_hp), 0.12)


func _apply_team_color(team_name: String) -> void:
	var color: Color = TEAM_COLORS.get(team_name, TEAM_COLORS["player"])
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left     = 2
	fill_style.corner_radius_top_right    = 2
	fill_style.corner_radius_bottom_left  = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
