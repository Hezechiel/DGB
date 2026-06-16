extends CharacterBody2D

# bojove vlastnosti hraca
@export var speed: float = 100.0
@export var max_hp: int = 500
var health_points: int

@export var invuln_time: float = 0.25 # (invulnerability window)
var invuln_left: float = 0.0

# vlastnosti Lightning projektilu
@export var bolt_scene: PackedScene
@export var fire_cooldown: float = 0.5
@export var attack_range: float = 50.0
var fire_left: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var health_bar: Control = $HealthBar


var last_direction := Vector2.DOWN #default pozera dole

func _ready() -> void:
	health_points = max_hp
	health_bar.init(max_hp, "player")
	add_to_group("team_player")
	BattleManager.register(self, "player")
	hurtbox.add_to_group("player_hurtbox")
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	InputR.clear_move_target() # zmaz stary ciel po reloade sceny

func _physics_process(delta):
	invuln_left = max(invuln_left - delta, 0.0)
	fire_left = max(fire_left - delta, 0.0)
	
	# 1) MOVE INPUT (tap-to-move)
	var move_dir : Vector2 = get_move_input()

	# 2) AUTO-ATTACK na najblizsieho enemy v dosahu
	var enemy := find_nearest_enemy()
	if enemy != null and fire_left <= 0.0:
		var dir := (enemy.global_position - global_position).normalized()
		fire_bolt(dir)
		fire_left = fire_cooldown
		last_direction = dir # animacia sa otoci k cielu
	
	# Normalizacia (aby diagonalna nebola rychlejsia)
	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		last_direction = move_dir
		update_animation(move_dir)
	else:
		update_idle_animation()
	
	velocity = velocity.move_toward(move_dir * speed, 500 * delta)
	move_and_slide()

func get_move_input() -> Vector2:
	# Tap-to-move (autoload InputRouter)
	if InputR.has_move_target:
		var to_target := InputR.move_target - global_position
		if to_target.length() <= 8.0:
			InputR.clear_move_target() # sme dost blizko, stop
			return Vector2.ZERO
		return to_target.normalized()

	return Vector2.ZERO

# =========================
# FIGHTING LOGIC
# =========================

func find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2 := attack_range * attack_range
	for child in get_parent().get_children():
		if child == self:
			continue
		if child is Node2D and child.is_in_group("team_enemy"):
			var d2: float = child.global_position.distance_squared_to(global_position)
			if d2 <= nearest_d2:
				nearest_d2 = d2
				nearest = child
	return nearest

func take_damage(amount: int) -> void:
	if invuln_left > 0.0:
		return
	
	health_points -= amount
	invuln_left = invuln_time
	
	# vizualny feedback (zatial jednoduchy)
	sprite.modulate.a = 0.4
	await get_tree().create_timer(0.08).timeout
	sprite.modulate.a = 1.0
	
	#print(health_points)

	health_bar.set_health(health_points)

	if health_points <= 0:
		print("PLAYER DEAD")
		get_tree().reload_current_scene()

func fire_bolt(dir: Vector2) -> void:
	if bolt_scene == null:
		push_error("Player: bolt_scene nie je nastavene!")
		return

	if dir == Vector2.ZERO:
		dir = last_direction
	
	var bolt := bolt_scene.instantiate()
		# bezpecne pridaj do sceny (niekedy sa hodi deferred)
	get_parent().add_child.call_deferred(bolt)
	
	# po pridani nastav poziciu/direction
	var start_pos = global_position + dir * 12.0
	bolt.call_deferred("setup", start_pos, dir)
	bolt.set("hit_group", "team_enemy")
	

# Tato funkcia sa zavola ked nieco vstupi do Hurtboxu
# V nasom modeli ale damage bide "tahat" enemy cez cooldown,
# takze tu zatial nemusis nic riesit.
func _on_hurtbox_area_entered(_area: Area2D) -> void:
	pass

# =========================
# ANIMATION LOGIC
# =========================

func update_animation(direction: Vector2) -> void:
	# Porovname absolutne hodnoty osi
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
	if abs(last_direction.x) > abs(last_direction.y):
		if last_direction.x > 0:
			sprite.play("right")
		else:
			sprite.play("left")
	else:
		if last_direction.y > 0:
			sprite.play("down")
		else:
			sprite.play("up")
