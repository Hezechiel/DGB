extends CharacterBody2D

# Pohyb enemy po mape
@export var speed: float = 30.0
@export var separation_radius: float = 5.0
@export var separation_strength: float = 1.3
@export var separation_update_interval: float = 0.10
var sep_timer: float = 0.0
var cached_sep: Vector2 = Vector2.ZERO
# Ak sa budú “rozliezať” príliš do strán, zníž separation_strength.
# Ak sa stále zlepia, zvýš separation_radius (10.0 az 14.0) alebo strength (1.0 až 2.0).
@export var seek_strength: float = 1.0
@export var max_neighbors: int = 8

# bojove vlastnosti nepriatela
@export var damage: int = 5
@export var attack_cooldown: float = 1.2
var attack_left: float = 0.0
var hurtbox_in_range: Area2D = null
var target: Node2D
@onready var attack_area: Area2D = $AttackArea
var enemy_manager: Node = null
@export var max_hp: int = 50
var hp: int

# animacia enemy
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var last_direction := Vector2.DOWN

func _ready() -> void:
	hp = max_hp
	add_to_group("enemies") # aby hrac vedel najst ciel pre auto-attack
	#attack_area.area_entered.connect(_on_attack_area_area_entered)
	#attack_area.area_exited.connect(_on_attack_area_area_exited)

# funkcie enemy
func _physics_process(delta: float) -> void:
	if target == null:
		return
	
	attack_left = max(attack_left - delta , 0.0)
	
	# 1) SEEK (na hraca)
	var to_target: Vector2 = target.global_position - global_position
	var seek_dir: Vector2 = to_target.normalized()
	
	# 2) SEPARATION (od ostatnych enemy)
	sep_timer -= delta
	if sep_timer <= 0.0:
		sep_timer = separation_update_interval
		cached_sep = compute_separation()
	var sep: Vector2 = cached_sep
	
	# 3) Kombinácia
	var steer: Vector2 = (seek_dir * seek_strength) + (sep * separation_strength)
	
	# fallback aby sa nezastavili, ked je steer nulovy
	if steer.length() < 0.001:
		steer = seek_dir
	
	var	direction: Vector2 = steer.normalized()
	
	last_direction = direction
	update_animation(direction)
	
	# velocity = velocity.move_toward(direction * speed, 500 * delta)
	velocity = direction * speed
	move_and_slide()
	
	if hurtbox_in_range != null and attack_left <= 0.0:
		if target != null and target.has_method("take_damage"):
			target.take_damage(damage)
		attack_left = attack_cooldown

func compute_separation() -> Vector2:
	var result := Vector2.ZERO
	var count := 0
	var r2 := separation_radius * separation_radius
	
	# POZOR: toto je stale drahe, ale uz menej
	for e in enemy_manager.enemies:
		if e == self:
			continue
		var other := e as Node2D
		var diff := global_position - other.global_position
		var d2 := diff.length_squared()
		
		if d2 > 0.0 and d2 < r2:
			# 1/sqrt(d2) je stale sqrt; da sa zjednodusit
			# pre prototyp staci 1/d2 (lacnejsie), bude to trochu "tvrdsie"
			result += diff / d2
			count += 1
			if count >= max_neighbors:
				break
	
	if count > 0:
		result /= float(count)
	
	return result

func update_animation(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			sprite.play("right")
		else:
			sprite.play("left")
	else:
		if direction.y > 0:
			sprite.play("down")
		else:
			sprite.play("up")
			
func update_idle_animation() -> void:
	# zatial nech ostane posledna animacia (bez idle setov)
	update_animation(last_direction)

func _on_attack_area_area_entered(area: Area2D) -> void:
	# filtruj iba hracov hurtbox
	if area.is_in_group("player_hurtbox"):
		hurtbox_in_range = area

func _on_attack_area_area_exited(area: Area2D) -> void:
	if area == hurtbox_in_range:
		hurtbox_in_range = null

func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()
