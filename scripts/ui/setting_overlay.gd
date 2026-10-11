extends Control
class_name SettingsOverlay

signal closed_requested
signal exit_requested
signal credits_requested

const GOD_ANIM := &"iddle_left"
# referencna vyska snimku — vsetci bohovia sa skaluju ROVNAKO,
# vzajomnu velkost (Zeus vs Poseidon) urcuje art, nie okno
const GOD_REF_FRAME_H := 400.0

@export var god_height_fill: float = 0.85   # podiel vysky okna
@export var god_foot_nudge: float = 0.0     # posun chodidiel, podiel vysky okna (+ = dole)

@onready var close_settings: TextureButton = $FrameFit/FrameRoot/CloseSettings
@onready var exit_button: Button = $FrameFit/FrameRoot/ContentArea/ScrollContainer/SettingsContent/ButtonRow/ExitButton
@onready var lock_camera_toggle: CheckButton = $FrameFit/FrameRoot/ContentArea/ScrollContainer/SettingsContent/LockCameraRow/LockCameraToggle
@onready var credits_button: Button = $FrameFit/FrameRoot/ContentArea/ScrollContainer/SettingsContent/ButtonRow/CreditsButton
@onready var god_window: Control = $FrameFit/FrameRoot/GodWindow
@onready var god_idle: AnimatedSprite2D = $FrameFit/FrameRoot/GodWindow/GodIdle

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	close_settings.pressed.connect(_on_close_settings_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	lock_camera_toggle.toggled.connect(_on_lock_camera_toggled)
	credits_button.pressed.connect(_on_credits_button_pressed)
	god_window.resized.connect(_layout_god)
	visible = false

#show_return_to_mainmenu_button sluzi na skritie alebo ukazanie Main Menu tlacidla
#toto tlacidlo nie je vzdy ziaduce na obrazovke
func open(show_return_to_mainmenu_button: bool = true) -> void:
	#print("menu opened")
	exit_button.visible = show_return_to_mainmenu_button
	# synchnronizuj checkbox so skutocnym stavom nastavenia
	lock_camera_toggle.button_pressed = Settings.lock_camera
	_refresh_god()
	visible = true

func close() -> void:
	#print("Close settings overlay function firred")
	visible = false
	god_idle.stop()  # skryty overlay nema co animovat
	#closed.emit()

# Aktivny boh (boh aktivneho decku) v lavom okne ramu.
func _refresh_god() -> void:
	var id := PlayerProfile.get_deck_hero()
	if not CardDB.has_hero(id):
		god_idle.visible = false
		return
	var frames := CardDB.get_hero(id).sprite_frames
	if frames == null or not frames.has_animation(GOD_ANIM):
		god_idle.visible = false
		return
	god_idle.sprite_frames = frames
	god_idle.flip_h = true
	god_idle.visible = true
	god_idle.play(GOD_ANIM)
	_layout_god()
	DebugLog.info("settings", "god: %s" % id)

# Node2D v Control sa neukladá kontajnerom — pozicia rucne cez resized
# (rovnaky problem ako hero showcase v main menu).
func _layout_god() -> void:
	var frames := god_idle.sprite_frames
	if frames == null or not frames.has_animation(GOD_ANIM):
		return
	var s := god_window.size.y * god_height_fill / GOD_REF_FRAME_H
	god_idle.scale = Vector2(s, s)
	var frame_h := frames.get_frame_texture(GOD_ANIM, 0).get_height()
	# bottom-center: chodidla na spodku okna (+ nudge)
	god_idle.position = Vector2(
		god_window.size.x / 2.0,
		god_window.size.y - frame_h * s / 2.0 + god_foot_nudge * god_window.size.y)

func _on_close_settings_pressed() -> void:
	#print("Close_request emited")
	closed_requested.emit()

func _on_credits_button_pressed() -> void:
	# Settings sa zatvori PRED vyziadanim Credits — oba su fullscreen overlay,
	# nechceme mat naraz otvorene oba naraz.
	close()
	credits_requested.emit()

func _on_exit_button_pressed() -> void:
	exit_requested.emit()

func _on_lock_camera_toggled(pressed: bool) -> void:
	Settings.set_lock_camera(pressed)
