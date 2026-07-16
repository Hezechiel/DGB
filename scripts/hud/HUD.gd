extends CanvasLayer
class_name HUD

signal exit_requested
signal recenter_camera_requested

## Node wired in arena.tscn inspector — hidden when settings are open.
@export var mobile_controls: CanvasLayer

#@onready var pause_button: TextureButton = $Root/PauseButton
@onready var pause_button: TouchScreenButton = $Root/PauseButton
@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var player_character_button: TouchScreenButton = $Root/PlayerCharacter
@onready var card_hand: CardHand = $CardHand
@onready var match_info_bar: MatchInfoBar = $MatchInfoBar
@onready var energy_bar: EnergyBar = $EnergyBar

const BUTTON_SIZE := 80.0
const MARGIN := 8.0

func _ready() -> void:
	#_apply_safe_area()
	pause_button.pressed.connect(_on_pause_pressed)
	player_character_button.pressed.connect(_on_player_character_pressed)
	setting_overlay.closed_requested.connect(_on_close_requested)
	setting_overlay.exit_requested.connect(_on_exit_requested)

#func _apply_safe_area() -> void:
	#var safe_rect := DisplayServer.get_display_safe_area()
	#var screen_size := Vector2(DisplayServer.screen_get_size())
	#if screen_size.x == 0.0:
		#return
	## Scale safe-area pixels (screen coords) down to viewport/UI coords.
	#var vp_size := get_viewport().get_visible_rect().size
	#var scale := vp_size / screen_size
	#var top_inset := maxf(0.0, safe_rect.position.y * scale.y)
	#var right_inset := maxf(0.0, (screen_size.x - safe_rect.end.x) * scale.x)
	#pause_button.offset_left = -(BUTTON_SIZE + right_inset + MARGIN)
	#pause_button.offset_right = -(right_inset + MARGIN)
	#pause_button.offset_top = top_inset + MARGIN
	#pause_button.offset_bottom = top_inset + MARGIN + BUTTON_SIZE

func _on_pause_pressed() -> void:
	#print("pause pressed")
	get_tree().paused = true
	if mobile_controls:
		mobile_controls.visible = false
	setting_overlay.open()

func _on_close_requested() -> void:
	setting_overlay.close()
	if mobile_controls:
		mobile_controls.visible = true
	get_tree().paused = false

func _on_exit_requested() -> void:
	setting_overlay.close()
	get_tree().paused = false
	exit_requested.emit()

func _on_player_character_pressed() -> void:
	# TouchScreenButton nespotrebuje event — potlac nasledujuci release aby
	# arena.gd nespustil tap-to-move na pozicii buttonu
	InputR.suppress_next_release()
	recenter_camera_requested.emit()

# ---------------------------------------------------------------------------
# PLACEHOLDER: func show_currency(amount: int) -> void — wire CurrencyCounter
# PLACEHOLDER: func show_seasonal_banner(event_id: String) -> void — SeasonalEventBanner
# PLACEHOLDER: func set_daily_rewards_available(has_reward: bool) -> void — DailyRewardsButton
# ---------------------------------------------------------------------------
