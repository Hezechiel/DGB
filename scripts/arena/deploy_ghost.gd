extends Node2D
# Placeholder preview kruh pre drag-to-deploy. Zelena = da sa deployovat,
# cervena = zakazane miesto. Pri spell kartach ma kruh REALNY polomer efektu
# a nad nim sa prehráva animovany zvitok. TODO: nahradit realnym previewom
# jednotky (silueta/duch) az budu assety.

@export var unit_radius: float = 24.0        # default pre unit karty
@export var color_valid := Color(0.2, 0.9, 0.3, 0.35)
@export var color_invalid := Color(0.9, 0.2, 0.2, 0.35)
@export var anim_scale: float = 0.25         # 260x340 sprity vs 64x64 svet
@export var anim_offset := Vector2(0, -60)   # zvitok kusok NAD kruhom

var _is_valid: bool = true
var _draw_radius: float = 0.0

func _ready() -> void:
	_draw_radius = unit_radius
	visible = false

func show_at(pos: Vector2, is_valid: bool) -> void:
	global_position = pos
	_is_valid = is_valid
	visible = true
	queue_redraw()

# Volane raz na zaciatku dragu — nastavi polomer kruhu a animaciu podla
# typu karty. Spell karty: kruh ma REALNY polomer efektu (spell.radius),
# takze hrac vidi presne to, co zasiahne. Unit karty: fixny maly kruh
# a ziadna animacia.
func configure_for_card(card: CardData) -> void:
	var anim: AnimatedSprite2D = $ScrollAnim
	if card != null and card.spell_data != null:
		_draw_radius = card.spell_data.radius
		var sf: SpriteFrames = card.spell_data.sprite_frames
		if sf != null and sf.has_animation(&"drag"):
			anim.sprite_frames = sf
			anim.scale = Vector2(anim_scale, anim_scale)
			anim.position = anim_offset
			anim.speed_scale = 1.0
			anim.visible = true
			anim.play(&"drag")
		else:
			anim.visible = false
	else:
		_draw_radius = unit_radius
		anim.visible = false
	queue_redraw()

func hide_ghost() -> void:
	visible = false
	$ScrollAnim.stop()
	$ScrollAnim.visible = false

func _draw() -> void:
	draw_circle(Vector2.ZERO, _draw_radius, color_valid if _is_valid else color_invalid)
