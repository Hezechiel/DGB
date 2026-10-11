extends Control
class_name FramedOverlay

# Spolocny ram s bohom pre fullscreen overlaye (Settings, Credits…).
# Odvodene sceny pridavaju vlastny obsah pod FrameFit/FrameRoot/ContentArea.
# Odvodene skripty, ktore prepisu _ready(), MUSIA volat super() ako prve —
# Godot 4 _ready automaticky nezretazi.
# Derived scripts that override _ready() MUST call super() first —
# Godot 4 does not chain _ready automatically.

const GOD_ANIM := &"iddle_left"
# referencna vyska snimku — vsetci bohovia sa skaluju ROVNAKO,
# vzajomnu velkost (Zeus vs Poseidon) urcuje art, nie okno
const GOD_REF_FRAME_H := 400.0
const TITLE_MAX_FONT := 26   # zakladna velkost na plate
const TITLE_MIN_FONT := 14   # pod toto nezmensovat

@export var god_height_fill: float = 0.85   # podiel vysky okna
@export var god_foot_nudge: float = 0.0     # posun chodidiel, podiel vysky okna (+ = dole)
@export var frame_texture: Texture2D        # null = nechaj texturu FrameArt zo sceny
@export var title_text: String = ""         # "" = TitleLabel skryty (titul je v arte)

@onready var dim: Control = $Dim
@onready var frame_root: Control = $FrameFit/FrameRoot
@onready var frame_art: TextureRect = $FrameFit/FrameRoot/FrameArt
@onready var god_window: Control = $FrameFit/FrameRoot/GodWindow
@onready var god_idle: AnimatedSprite2D = $FrameFit/FrameRoot/GodWindow/GodIdle
@onready var title_label: Label = $FrameFit/FrameRoot/TitleLabel
@onready var content_area: MarginContainer = $FrameFit/FrameRoot/ContentArea
@onready var close_button: TextureButton = $FrameFit/FrameRoot/CloseButton

func _ready() -> void:
	if frame_texture != null:
		frame_art.texture = frame_texture
	set_title(title_text)
	close_button.pressed.connect(_on_frame_close_pressed)
	god_window.resized.connect(_layout_god)
	# plate meni velkost s AspectRatioContainerom → titul sa znova zmesti
	title_label.resized.connect(_fit_title)

# "" = TitleLabel skryty (titul je v arte).
func set_title(text: String) -> void:
	title_text = text
	title_label.text = text
	title_label.visible = not text.is_empty()
	_fit_title()

# Zmensi font titulu, kym sa nezmesti na plate (napr. "Encyclopedia").
func _fit_title() -> void:
	if not title_label.visible:
		return
	var avail := _title_slot_width()
	if avail <= 0.0:
		return  # layout este nebezal — dorovna prvy resized
	var font := title_label.get_theme_font("font")
	var outline := title_label.get_theme_constant("outline_size")
	var text := title_label.text.to_upper()  # label ma uppercase = true
	var fs := TITLE_MAX_FONT
	while fs > TITLE_MIN_FONT and \
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2 * outline > avail:
		fs -= 1
	title_label.add_theme_font_size_override("font_size", fs)

# Sirka slotu na plate z anchorov — NIE title_label.size.x: Label bez clip_text
# ma min. sirku = sirka textu, takze pretekajuci titul by si label sam roztiahol
# a nikdy by sa nezmensil.
func _title_slot_width() -> float:
	return (title_label.anchor_right - title_label.anchor_left) * frame_root.size.x \
		+ title_label.offset_right - title_label.offset_left

# Volat z open() odvodeneho overlayu.
func _frame_opened() -> void:
	_refresh_god()

# Volat z close() odvodeneho overlayu — skryty overlay nema co animovat.
func _frame_closed() -> void:
	god_idle.stop()

# Virtual — odvodene overlaye prepisu (napr. emit closed signalu).
func _on_frame_close_pressed() -> void:
	pass

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
	DebugLog.info("frame", "god: %s" % id)

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
