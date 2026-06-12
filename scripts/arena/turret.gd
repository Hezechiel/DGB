extends StaticBody2D

# Vezicka — staticka obrana. Strazi okolie (DetectionRange) a strieli
# LightningBolty na enemy v dosahu.
#
# Pozn.: AnimatedSprite2D.frame indexuje len v ramci AKTUALNEJ animacie,
# nie cely spritesheet. Damage stavy (riadok 1 sheetu) su preto 4 frames
# v animacii "damaged" a vyberaju sa cez .frame (0..3).
const FRAME_DESTROYED := 3 # row 1 col 3 — znicena vezicka (0% hp wreck)

@export var max_hp: int = 300
@export var max_range: float = 180.0        # detection radius in pixels
@export var fire_cooldown: float = 1.5      # seconds between shots
@export var projectile_damage: int = 20
@export var armor: float = 0.0              # flat damage reduction (0 = no armor)
@export var aggro_drop_range: float = 240.0 # target released beyond this distance
@export var bolt_scene: PackedScene         # assign LightningBolt.tscn in Inspector

var hp: int
var fire_left: float = 0.0
var current_target: Node2D = null
var is_stunned: bool = false
var stun_timer: float = 0.0
var restore_hp_per_sec: float = 0.0         # set by repair abilities; 0 = no regen
var regen_buffer: float = 0.0               # zbiera zlomky HP (int heal by ich kazdy frame zahodil)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_range: Area2D = $DetectionRange
@onready var detection_shape: CollisionShape2D = $DetectionRange/CollisionShape2D


func _ready() -> void:
	hp = max_hp
	add_to_group("turrets")

	# polomer detekcie podla exportu — duplicate, aby viac veziciek
	# nezdielalo jeden CircleShape2D resource
	var circle := detection_shape.shape.duplicate() as CircleShape2D
	circle.radius = max_range
	detection_shape.shape = circle

	detection_range.body_entered.connect(_on_body_entered)
	detection_range.body_exited.connect(_on_body_exited)

	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
		return

	# regen (repair ability)
	if restore_hp_per_sec > 0.0:
		regen_buffer += restore_hp_per_sec * delta
		if regen_buffer >= 1.0:
			var whole := floorf(regen_buffer)
			regen_buffer -= whole
			heal(whole)

	fire_left = max(fire_left - delta, 0.0)

	# ciel mohol medzitym umriet / zmiznut zo stromu
	if current_target != null and not is_instance_valid(current_target):
		current_target = null

	if current_target != null:
		if current_target.global_position.distance_to(global_position) > aggro_drop_range:
			_drop_target()

	if current_target != null and fire_left <= 0.0:
		_fire_at(current_target)
		fire_left = fire_cooldown


# =========================
# DAMAGE / HEAL / STUN
# =========================

func take_damage(amount: int) -> void:
	if hp <= 0:
		return # uz je to vrak

	var effective := maxi(1, amount - int(armor))
	hp -= effective

	if hp <= 0:
		_on_destroyed()
	else:
		_update_damage_visual()


func heal(amount: float) -> void:
	if hp <= 0:
		return # vrak sa regenom neopravuje (revive bude riesit ability)

	hp = mini(max_hp, hp + int(amount))
	_update_damage_visual()


func apply_stun(duration: float) -> void:
	is_stunned = true
	stun_timer = max(stun_timer, duration) # dlhsi stun vyhrava


func taunt(new_target: Node2D) -> void:
	# nasilu prepise aktualny aggro (pre buduce ability)
	current_target = new_target


# =========================
# FIRING
# =========================

func _fire_at(target: Node2D) -> void:
	if bolt_scene == null:
		push_error("Turret: bolt_scene nie je nastavene!")
		return

	var dir := (target.global_position - global_position).normalized()

	var bolt := bolt_scene.instantiate()
	bolt.set("damage", projectile_damage)
	get_parent().add_child.call_deferred(bolt)

	# po pridani nastav poziciu/direction
	bolt.call_deferred("setup", global_position, dir)


# =========================
# VISUALS
# =========================

func _update_damage_visual() -> void:
	var ratio := float(hp) / float(max_hp)

	if ratio > 0.75:
		if sprite.animation != &"idle" or not sprite.is_playing():
			sprite.play("idle")
		return

	# staticky damage frame z riadku 1 (animacia "damaged")
	var col := 0
	if ratio <= 0.25:
		col = 2
	elif ratio <= 0.5:
		col = 1

	sprite.stop()
	sprite.animation = &"damaged"
	sprite.frame = col


func _on_destroyed() -> void:
	hp = 0
	current_target = null

	sprite.stop()
	sprite.animation = &"damaged"
	sprite.frame = FRAME_DESTROYED

	# vrak ostava na mape len ako vizual — bez kolizie a detekcie
	$CollisionShape2D.set_deferred("disabled", true)
	detection_shape.set_deferred("disabled", true)
	remove_from_group("turrets")
	set_physics_process(false)


# =========================
# TARGETING
# =========================

func _on_body_entered(body: Node2D) -> void:
	if current_target == null and body.is_in_group("enemies"):
		current_target = body


func _on_body_exited(body: Node2D) -> void:
	if body == current_target:
		_drop_target()


func _drop_target() -> void:
	current_target = null
