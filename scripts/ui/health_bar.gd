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
var _pending_remaining: float = 0.0   # zostavajuci HoT — kresli tmavozeleny pas pred HP
var _tween: Tween = null

@onready var bar: ProgressBar = $Bar
@onready var pending_bar: ProgressBar = $PendingBar


func _ready() -> void:
	if not always_visible:
		visible = false


# Call once from parent _ready() after hp vars are set.
func init(max_value: int, team_name: String) -> void:
	_max_hp = max_value
	_current_hp = max_value
	bar.max_value = float(max_value)
	bar.value    = float(max_value)
	pending_bar.max_value = float(max_value)
	pending_bar.value = float(max_value)
	_pending_remaining = 0.0
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

	_update_pending_bar()


# Call from hero heal handlers — remaining is the HoT amount still to come.
func set_pending_heal(remaining: float) -> void:
	_pending_remaining = maxf(remaining, 0.0)
	_update_pending_bar()


# Tmavozeleny "pending heal" pas pred aktualnym HP — kotvi sa na _current_hp,
# takze ho treba prepocitat aj pri kazdom set_health(), nie len pri HoT ticku
# (inak by po obycajnom damage ostal visiet stary pas).
func _update_pending_bar() -> void:
	pending_bar.value = clampf(float(_current_hp) + _pending_remaining, 0.0, float(_max_hp))


func _apply_team_color(team_name: String) -> void:
	var color: Color = TEAM_COLORS.get(team_name, TEAM_COLORS["player"])
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left     = 2
	fill_style.corner_radius_top_right    = 2
	fill_style.corner_radius_bottom_left  = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)


# === DASH STRIP ===
# Tenky zlty segmentovany pas pod HP barom — LEN lokalny hrdina (player.gd
# vola init_dash). HealthBar.tscn je zdielany s enemy hrdinom, jednotkami aj
# vezami: tie init_dash nevolaju → _dash_max = 0 → nic sa nekresli.
# Kreslene v kode (_draw), ziadne nove nody. Segmenty = DashMeter.value
# rozlozene cez max_charges (dalsi segment sa plni az po naplneni predosleho).
# Skryva sa spolu s Controlom (mrtvy hrdina → visible = false).
const DASH_STRIP_GAP_Y := 1.0     # px pod Bar
const DASH_STRIP_HEIGHT := 2.0
const DASH_SEG_GAP := 1.0
const DASH_COLOR_READY := Color(0.95, 0.8, 0.15)
const DASH_COLOR_CHARGING := Color(0.95, 0.8, 0.15, 0.45)
const DASH_COLOR_EMPTY := Color(0.12, 0.12, 0.12, 0.85)  # rovnaka ako pozadie Baru

var _dash_max: int = 0   # 0 = strip vypnuty (default pre vsetkych okrem hraca)
var _dash_value: float = 0.0

func init_dash(max_charges: int) -> void:
	_dash_max = maxi(max_charges, 0)
	_dash_value = float(_dash_max)
	queue_redraw()

func set_dash(value: float) -> void:
	if _dash_max == 0 or is_equal_approx(value, _dash_value):
		return
	_dash_value = value
	queue_redraw()

func _draw() -> void:
	if _dash_max == 0:
		return
	var width := bar.size.x
	var y := bar.position.y + bar.size.y + DASH_STRIP_GAP_Y
	var seg_w := (width - DASH_SEG_GAP * (_dash_max - 1)) / _dash_max
	for i in _dash_max:
		var x := i * (seg_w + DASH_SEG_GAP)
		draw_rect(Rect2(x, y, seg_w, DASH_STRIP_HEIGHT), DASH_COLOR_EMPTY)
		var fill := clampf(_dash_value - i, 0.0, 1.0)
		if fill > 0.0:
			draw_rect(Rect2(x, y, seg_w * fill, DASH_STRIP_HEIGHT),
					DASH_COLOR_READY if fill >= 1.0 else DASH_COLOR_CHARGING)
