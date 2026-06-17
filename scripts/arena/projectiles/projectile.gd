extends Node2D

# Projektil sleduje konkretny ciel (Node2D), pohybuje sa k nemu a pri dosiahnutí
# zasahne len jeho. Znici sa okamzite po zasahu alebo ak ciel zanikne.

@export var speed: float        = 100.0
@export var damage: int         = 25
@export var max_lifetime: float = 3.0   # poistka — znici sa aj bez zasahu

# "zasiahnutá" vzdialenost — distance_squared pre vyhnutie sqrt kazdy frame
const ARRIVAL_DIST_SQ: float = 12.0 * 12.0

var _target: Node2D    = null
var _lifetime: float   = 0.0
var _direction: Vector2 = Vector2.RIGHT   # posledny vypocitany smer
var _aim_tick: int     = 0                # pocitadlo pre throttlovanie preracovania smeru

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _current_anim: String = ""


# Volane deferred po add_child — nastavi poziciu a ciel
func setup(start_pos: Vector2, target: Node2D) -> void:
	global_position = start_pos
	_target    = target
	_lifetime  = max_lifetime
	_aim_tick  = 0
	if is_instance_valid(_target):
		_direction = (_target.global_position - start_pos).normalized()
		_update_sprite_direction(_direction)


func _physics_process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return

	# ciel zanikol skor nez projektil dorazil
	if not is_instance_valid(_target):
		queue_free()
		return

	# smer prerataj len kazdy 3. frame — plynulejsi pohyb, menej vypoctov
	_aim_tick += 1
	if _aim_tick >= 3:
		_aim_tick = 0
		_direction = (_target.global_position - global_position).normalized()
		_update_sprite_direction(_direction)

	global_position += _direction * speed * delta

	# kontrola pristupu — zasah pri dostatocnej blizkosti
	if global_position.distance_squared_to(_target.global_position) <= ARRIVAL_DIST_SQ:
		if _target.has_method("take_damage"):
			_target.take_damage(damage)
		queue_free()


# =========================
# ANIMACIA SMERU (8 smerov)
# =========================

func _update_sprite_direction(dir: Vector2) -> void:
	if dir.length_squared() == 0.0:
		return

	var angle := rad_to_deg(dir.angle())
	var anim: String

	if   angle >= -22.5  and angle <  22.5:  anim = "right"
	elif angle >=  22.5  and angle <  67.5:  anim = "down_right"
	elif angle >=  67.5  and angle < 112.5:  anim = "down"
	elif angle >= 112.5  and angle < 157.5:  anim = "down_left"
	elif angle >= -67.5  and angle < -22.5:  anim = "up_right"
	elif angle >= -112.5 and angle < -67.5:  anim = "up"
	elif angle >= -157.5 and angle < -112.5: anim = "up_left"
	else:                                     anim = "left"

	if anim != _current_anim:
		_current_anim = anim
		sprite.play(anim)
